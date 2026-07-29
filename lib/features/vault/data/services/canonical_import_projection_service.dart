import 'dart:typed_data';

import '../../../../core/crypto/sodium_provider.dart';
import '../../domain/entities/import_draft.dart';
import '../../domain/entities/entry_entity.dart';
import '../datasources/vault_remote_datasource.dart';
import 'vault_protocol/vault_protocol_aad.dart';
import 'vault_protocol/vault_protocol_bytes.dart';
import 'vault_protocol/vault_protocol_envelope_service.dart';
import 'vault_protocol/vault_protocol_kdf.dart';
import 'vault_protocol/vault_protocol_signature_service.dart';
import 'vault_rotation_crypto_service.dart';

/// Builds complete protocol-2 import transitions entirely on-device.
class CanonicalImportProjectionService {
  CanonicalImportProjectionService({
    required VaultRemoteDatasource vaults,
    required VaultRotationCryptoService keys,
    required VaultEnvelopeCryptography envelopes,
    Future<Uint8List> Function()? randomEntryKey,
  }) : _vaults = vaults,
       _keys = keys,
       _envelopes = envelopes,
       _randomEntryKey = randomEntryKey ?? _secureRandomEntryKey;

  final VaultRemoteDatasource _vaults;
  final VaultRotationCryptoService _keys;
  final VaultEnvelopeCryptography _envelopes;
  final Future<Uint8List> Function() _randomEntryKey;

  static Future<Uint8List> _secureRandomEntryKey() async {
    final sodium = await SodiumProvider.instance();
    return sodium.randombytes.buf(32);
  }

  Future<List<Map<String, dynamic>>> prepareCredentialBatch({
    required String vaultId,
    required List<String> entryIds,
    required List<ImportEntryDraft> drafts,
    required Uint8List memberPrivateKey,
  }) async {
    if (entryIds.length != drafts.length ||
        drafts.isEmpty ||
        drafts.length > 500) {
      throw const FormatException('Invalid import batch');
    }
    final vault = await _vaults.getEncryptedVault(vaultId);
    final organizationId = vault['organizationId'] as String;
    final generation = vault['memberKeyGeneration'] as int;
    final epoch = Map<String, dynamic>.from(vault['currentKeyEpoch'] as Map);
    final vkVersion = epoch['vaultKeyVersion'] as int;
    final vdkVersion = epoch['vdkVersion'] as int;
    Uint8List? vaultKey;
    Uint8List? discoveryKey;
    final sensitive = <Uint8List>[];
    try {
      vaultKey = await _keys.openMemberVaultKey(
        Map<String, dynamic>.from(vault['memberVaultKey'] as Map),
        memberPrivateKey,
      );
      discoveryKey = await _keys.openDiscoveryKey(
        Map<String, dynamic>.from(vault['discoveryKey'] as Map),
        vaultKey,
      );
      final output = <Map<String, dynamic>>[];
      for (var index = 0; index < drafts.length; index++) {
        final draft = drafts[index];
        if (draft.type.toWire() != 1) {
          throw const FormatException('Import type is not supported');
        }
        final entryId = entryIds[index];
        final entryDek = await _randomEntryKey();
        if (entryDek.length != 32) {
          throw const FormatException('Entry DEK must be 32 bytes');
        }
        sensitive.add(entryDek);
        final common = <String, Object?>{
          'organizationId': organizationId,
          'vaultId': vaultId,
          'entryId': entryId,
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
        Future<Map<String, dynamic>> projection({
          required VaultAadProfile profile,
          required VaultKdfPurpose purpose,
          required Map<String, dynamic> value,
          required Uint8List baseKey,
          required int projectionKind,
          required int keyVersion,
          required String revisionField,
        }) async {
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
          sensitive.add(key);
          final plaintext = VaultProtocolBytes.utf8Encode(
            canonicalizeVaultJson(value),
          );
          sensitive.add(plaintext);
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
            plaintext: plaintext,
            key: key,
          );
          return {
            ...context,
            'header': {
              ...context['header']! as Map,
              'nonce': encrypted['nonce'],
            },
            'ciphertext': encrypted['ciphertext'],
          };
        }

        final content = <String, dynamic>{...draft.payload, 'type': 1};
        final memberIndex = <String, dynamic>{
          'memberLabel': draft.label,
          'entryType': 1,
          if (draft.icon?.isNotEmpty == true) 'iconReference': draft.icon,
          'searchFields': [
            draft.label,
            if (draft.description?.isNotEmpty == true) draft.description,
            if (content['username'] is String) content['username'],
            if (content['url'] is String) content['url'],
          ],
          if (content['url'] is String) 'autofillDomains': [content['url']],
        };
        const policy = <String, dynamic>{
          'discoverable': true,
          'fields': <String, String>{
            'agentLabel': 'discovery',
            'description': 'never',
            'notes': 'onGrantValue',
            'username': 'onGrantValue',
            'urlDomain': 'never',
            'url': 'onGrantValue',
            'password': 'onGrantValue',
            'totp': 'onGrantDerived',
          },
        };
        final memberSecret = <String, dynamic>{
          'schemaVersion': 1,
          'memberLabel': draft.label,
          'agentLabel': draft.label,
          if (draft.description?.isNotEmpty == true)
            'description': draft.description,
          'entryType': 1,
          if (draft.icon?.isNotEmpty == true) 'iconReference': draft.icon,
          'content': content,
          'agentVisibilityPolicy': policy,
        };
        final discovery = <String, dynamic>{
          'schemaVersion': 1,
          'agentLabel': draft.label,
          'entryType': 1,
          'capabilities': const ['get', 'inject'],
          'fields': const <String, String>{},
        };
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
        output.add({
          'entryId': entryId,
          'entryKey': {
            ...wrapperContext,
            'header': {
              ...wrapperContext['header']! as Map,
              'nonce': wrapped['nonce'],
            },
            'wrappedEntryDekByVk': wrapped['ciphertext'],
          },
          'memberIndex': await projection(
            profile: VaultAadProfile.memberIndex,
            purpose: VaultKdfPurpose.memberIndex,
            value: memberIndex,
            baseKey: entryDek,
            projectionKind: 2,
            keyVersion: 1,
            revisionField: 'memberIndexRevision',
          ),
          'memberSecret': await projection(
            profile: VaultAadProfile.memberSecret,
            purpose: VaultKdfPurpose.memberSecret,
            value: memberSecret,
            baseKey: entryDek,
            projectionKind: 3,
            keyVersion: 1,
            revisionField: 'revision',
          ),
          'agentDiscovery': await projection(
            profile: VaultAadProfile.agentDiscovery,
            purpose: VaultKdfPurpose.agentDiscovery,
            value: discovery,
            baseKey: discoveryKey,
            projectionKind: 4,
            keyVersion: vdkVersion,
            revisionField: 'agentDiscoveryRevision',
          ),
          'grantEnvelopes': const <Object>[],
        });
      }
      return output;
    } finally {
      for (final value in [vaultKey, discoveryKey, ...sensitive]) {
        value?.fillRange(0, value.length, 0);
      }
    }
  }
}
