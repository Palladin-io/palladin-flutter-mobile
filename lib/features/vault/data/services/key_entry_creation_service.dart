import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../domain/entities/entry_entity.dart';
import '../datasources/entry_remote_datasource.dart';
import '../datasources/vault_remote_datasource.dart';
import 'vault_protocol/vault_protocol_aad.dart';
import 'vault_protocol/vault_protocol_bytes.dart';
import 'vault_protocol/vault_protocol_envelope_service.dart';
import 'vault_protocol/vault_protocol_kdf.dart';
import 'vault_protocol/vault_protocol_signature_service.dart';
import 'vault_rotation_crypto_service.dart';

/// Creates one canonical Key revision without exposing plaintext to the server.
final class KeyEntryCreationService {
  KeyEntryCreationService({
    required EntryRemoteDatasource entries,
    required VaultRemoteDatasource vaults,
    required VaultRotationCryptoService keys,
    required VaultEnvelopeCryptography envelopes,
    Future<Uint8List> Function()? randomEntryKey,
  }) : _entries = entries,
       _vaults = vaults,
       _keys = keys,
       _envelopes = envelopes,
       _randomEntryKey = randomEntryKey ?? _secureRandomEntryKey;

  final EntryRemoteDatasource _entries;
  final VaultRemoteDatasource _vaults;
  final VaultRotationCryptoService _keys;
  final VaultEnvelopeCryptography _envelopes;
  final Future<Uint8List> Function() _randomEntryKey;

  static Future<Uint8List> _secureRandomEntryKey() async {
    final sodium = await SodiumProvider.instance();
    return sodium.randombytes.buf(32);
  }

  Future<EntryEntity> create({
    required String vaultId,
    required String label,
    required String description,
    required String icon,
    required Map<String, dynamic> content,
    required Uint8List memberPrivateKey,
  }) async {
    final vault = await _vaults.getEncryptedVault(vaultId);
    final entryId = await _entries.issueCreationChallenge(vaultId);
    final organizationId = vault['organizationId'] as String;
    final generation = vault['memberKeyGeneration'] as int;
    final epoch = Map<String, dynamic>.from(vault['currentKeyEpoch'] as Map);
    final vkVersion = epoch['vaultKeyVersion'] as int;
    final vdkVersion = epoch['vdkVersion'] as int;
    Uint8List? vaultKey;
    Uint8List? discoveryKey;
    Uint8List? entryDek;
    final derived = <Uint8List>[];
    final plaintexts = <Uint8List>[];
    try {
      vaultKey = await _keys.openMemberVaultKey(
        Map<String, dynamic>.from(vault['memberVaultKey'] as Map),
        memberPrivateKey,
      );
      discoveryKey = await _keys.openDiscoveryKey(
        Map<String, dynamic>.from(vault['discoveryKey'] as Map),
        vaultKey,
      );
      entryDek = await _randomEntryKey();
      if (entryDek.length != 32) {
        throw const FormatException('Entry DEK must be 32 bytes');
      }
      final common = <String, Object?>{
        'organizationId': organizationId,
        'vaultId': vaultId,
        'entryId': entryId,
      };
      final memberIndex = <String, dynamic>{
        'memberLabel': label,
        'entryType': 'KEY',
        'searchFields': [label, if (description.isNotEmpty) description],
        if (icon.isNotEmpty) 'iconReference': icon,
      };
      final policy = <String, dynamic>{'discoverable': true, 'fields': {}};
      final memberSecret = <String, dynamic>{
        'schemaVersion': 1,
        'memberLabel': label,
        'agentLabel': label,
        if (description.isNotEmpty) 'description': description,
        if (icon.isNotEmpty) 'iconReference': icon,
        'entryType': 'KEY',
        'content': content,
        'agentVisibilityPolicy': policy,
      };
      final discovery = <String, dynamic>{
        'schemaVersion': 1,
        'agentLabel': label,
        'entryType': 'KEY',
        'capabilities': ['get', 'inject'],
        'fields': <String, String>{},
      };
      Map<String, dynamic> header(int projection, int keyVersion) => {
        'protocolVersion': 2,
        'algorithmSuite': 1,
        'resourceKind': 2,
        'projectionKind': projection,
        'resourceRevision': '1',
        'keyVersion': keyVersion,
        'memberKeyGeneration': generation,
        'nonce': '',
      };
      Future<Map<String, dynamic>> projection(
        VaultAadProfile profile,
        VaultKdfPurpose purpose,
        Map<String, dynamic> value,
        Uint8List baseKey,
        int projectionKind,
        int keyVersion,
        String revisionField,
      ) async {
        final key = deriveVaultProjectionKey(
          baseKey,
          VaultKdfContext(
            purpose: purpose,
            resourceKind: 2,
            organizationId: organizationId,
            vaultId: vaultId,
            entryId: entryId,
            keyVersion: keyVersion,
            memberKeyGeneration: generation,
          ),
        );
        derived.add(key);
        final bytes = VaultProtocolBytes.utf8Encode(
          canonicalizeVaultJson(value),
        );
        plaintexts.add(bytes);
        final context = <String, Object?>{
          ...common,
          revisionField: '1',
          if (profile == VaultAadProfile.memberSecret) 'operation': 1,
          if (profile == VaultAadProfile.agentDiscovery)
            'vdkVersion': vdkVersion,
          'header': header(projectionKind, keyVersion),
        };
        final encrypted = await _envelopes.encrypt(
          profile: profile,
          context: context,
          plaintext: bytes,
          key: key,
        );
        return {
          ...context,
          'header': {...context['header']! as Map, 'nonce': encrypted['nonce']},
          'ciphertext': encrypted['ciphertext'],
        };
      }

      final wrapperContext = <String, Object?>{
        ...common,
        'wrapperRevision': '1',
        'keyVersion': 1,
        'memberKeyGeneration': generation,
        'wrappingKeyVersion': vkVersion,
        'header': header(8, 1),
      };
      final wrapped = await _envelopes.encrypt(
        profile: VaultAadProfile.entryKeyWrapper,
        context: wrapperContext,
        plaintext: entryDek,
        key: vaultKey,
      );
      final indexEnvelope = await projection(
        VaultAadProfile.memberIndex,
        VaultKdfPurpose.memberIndex,
        memberIndex,
        entryDek,
        2,
        1,
        'memberIndexRevision',
      );
      final secretEnvelope = await projection(
        VaultAadProfile.memberSecret,
        VaultKdfPurpose.memberSecret,
        memberSecret,
        entryDek,
        3,
        1,
        'revision',
      );
      final discoveryEnvelope = await projection(
        VaultAadProfile.agentDiscovery,
        VaultKdfPurpose.agentDiscovery,
        discovery,
        discoveryKey,
        4,
        vdkVersion,
        'agentDiscoveryRevision',
      );
      final request = <String, dynamic>{
        'entryId': entryId,
        'entryKey': {
          ...wrapperContext,
          'header': {
            ...wrapperContext['header']! as Map,
            'nonce': wrapped['nonce'],
          },
          'wrappedEntryDekByVk': wrapped['ciphertext'],
        },
        'memberIndex': indexEnvelope,
        'memberSecret': secretEnvelope,
        'agentDiscovery': discoveryEnvelope,
        'grantEnvelopes': <Object>[],
      };
      try {
        await _entries.createCanonicalEntry(vaultId, request);
      } on DioException catch (error) {
        if (error.response != null) rethrow;
        // Retry the exact same immutable transition. The backend recognizes
        // exact-create retries, so a lost 201 cannot create a second head.
        await _entries.createCanonicalEntry(vaultId, request);
      }
      final now = DateTime.now().toUtc();
      return EntryEntity(
        id: entryId,
        vaultId: vaultId,
        label: label,
        description: description.isEmpty ? null : description,
        icon: icon.isEmpty ? null : icon,
        type: EntryType.key,
        createdAt: now,
        updatedAt: now,
      );
    } finally {
      for (final value in [
        vaultKey,
        discoveryKey,
        entryDek,
        ...derived,
        ...plaintexts,
      ]) {
        value?.fillRange(0, value.length, 0);
      }
    }
  }
}
