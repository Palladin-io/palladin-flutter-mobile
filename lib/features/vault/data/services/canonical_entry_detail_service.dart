import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../domain/entities/entry_entity.dart';
import '../datasources/entry_remote_datasource.dart';
import '../datasources/vault_remote_datasource.dart';
import 'vault_protocol/vault_protocol_aad.dart';
import 'vault_protocol/vault_protocol_bytes.dart';
import 'vault_protocol/vault_protocol_envelope_service.dart';
import 'vault_protocol/vault_protocol_kdf.dart';
import 'vault_protocol/vault_protocol_signature_service.dart';
import 'vault_rotation_crypto_service.dart';

enum CanonicalEntryDetailError {
  conflict,
  corrupt,
  forbidden,
  notFound,
  network,
}

final class CanonicalEntryDetailException implements Exception {
  const CanonicalEntryDetailException(this.kind);
  final CanonicalEntryDetailError kind;
}

final class CanonicalEntrySnapshot {
  const CanonicalEntrySnapshot({
    required this.entry,
    required this.payload,
    required this.secret,
  });
  final Map<String, dynamic> entry;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> secret;
}

/// Opens and replaces canonical Entry projections without a legacy fallback.
///
/// Plaintext and key material exist only in method-local memory and are wiped
/// in `finally` paths. The update is one optimistic backend transaction: a
/// new immutable MemberSecret revision and the matching MemberIndex and
/// AgentDiscovery heads either all advance or none do.
class CanonicalEntryDetailService {
  CanonicalEntryDetailService({
    required EntryRemoteDatasource entries,
    required VaultRemoteDatasource vaults,
    required VaultRotationCryptoService keys,
    required VaultEnvelopeCryptography envelopes,
  }) : _entries = entries,
       _vaults = vaults,
       _keys = keys,
       _envelopes = envelopes;

  final EntryRemoteDatasource _entries;
  final VaultRemoteDatasource _vaults;
  final VaultRotationCryptoService _keys;
  final VaultEnvelopeCryptography _envelopes;

  Future<CanonicalEntrySnapshot> reveal({
    required EntryEntity expected,
    required Uint8List memberPrivateKey,
  }) async {
    Uint8List? vaultKey;
    Uint8List? entryDek;
    Uint8List? secretKey;
    Uint8List? plaintext;
    try {
      final vault = await _vaults.getEncryptedVault(expected.vaultId);
      final entry = await _entries.getCanonicalEntry(
        expected.vaultId,
        expected.id,
      );
      _validateScope(entry, expected);
      final generation = _int(vault, 'memberKeyGeneration');
      vaultKey = await _keys.openMemberVaultKey(
        _map(vault, 'memberVaultKey'),
        memberPrivateKey,
      );
      final wrapper = _map(entry, 'entryKey');
      final wrapperGeneration = _int(wrapper, 'memberKeyGeneration');
      if (wrapperGeneration > generation) {
        throw const FormatException('Entry key generation is from the future');
      }
      entryDek = await _envelopes.decrypt(
        profile: VaultAadProfile.entryKeyWrapper,
        envelope: wrapper,
        key: vaultKey,
        expected: VaultEnvelopeExpectations(
          aadContext: wrapper,
          minimumMemberKeyGeneration: wrapperGeneration,
        ),
      );
      if (entryDek.length != 32) throw const FormatException('Invalid DEK');
      final secret = _map(entry, 'memberSecret');
      final header = _map(secret, 'header');
      if (header['keyVersion'] != entry['currentKeyVersion'] ||
          header['memberKeyGeneration'] != wrapperGeneration ||
          secret['revision'] != entry['currentRevision']) {
        throw const FormatException('MemberSecret head mismatch');
      }
      secretKey = deriveVaultProjectionKey(
        entryDek,
        VaultKdfContext(
          purpose: VaultKdfPurpose.memberSecret,
          resourceKind: 2,
          organizationId: entry['organizationId'] as String,
          vaultId: expected.vaultId,
          entryId: expected.id,
          keyVersion: _int(header, 'keyVersion'),
          memberKeyGeneration: _int(header, 'memberKeyGeneration'),
        ),
      );
      plaintext = await _envelopes.decrypt(
        profile: VaultAadProfile.memberSecret,
        envelope: secret,
        key: secretKey,
        expected: VaultEnvelopeExpectations(
          aadContext: secret,
          minimumMemberKeyGeneration: wrapperGeneration,
        ),
      );
      final value = _decodeCanonicalObject(plaintext);
      final payload = value['content'];
      if (value['schemaVersion'] != 1 || payload is! Map) {
        throw const FormatException('Malformed MemberSecret');
      }
      return CanonicalEntrySnapshot(
        entry: entry,
        secret: value,
        payload: Map<String, dynamic>.from(payload),
      );
    } on DioException catch (error) {
      throw CanonicalEntryDetailException(_classifyDio(error));
    } on FormatException {
      throw const CanonicalEntryDetailException(
        CanonicalEntryDetailError.corrupt,
      );
    } finally {
      _wipe([vaultKey, entryDek, secretKey, plaintext]);
    }
  }

  Future<EntryEntity> update({
    required CanonicalEntrySnapshot snapshot,
    required EntryEntity expected,
    required String label,
    required String description,
    required String icon,
    required EntryType type,
    required Map<String, dynamic> content,
    required Uint8List memberPrivateKey,
  }) async {
    Uint8List? vaultKey;
    Uint8List? discoveryKey;
    Uint8List? entryDek;
    final derived = <Uint8List>[];
    final plaintexts = <Uint8List>[];
    try {
      _validateScope(snapshot.entry, expected);
      final vault = await _vaults.getEncryptedVault(expected.vaultId);
      final organizationId = snapshot.entry['organizationId'] as String;
      if (vault['organizationId'] != organizationId) {
        throw const FormatException('Vault organization mismatch');
      }
      final generation = _int(vault, 'memberKeyGeneration');
      final epoch = _map(vault, 'currentKeyEpoch');
      final vdkVersion = _int(epoch, 'vdkVersion');
      final wrapper = _map(snapshot.entry, 'entryKey');
      final wrapperGeneration = _int(wrapper, 'memberKeyGeneration');
      if (wrapperGeneration > generation) {
        throw const FormatException('Entry key generation is from the future');
      }
      vaultKey = await _keys.openMemberVaultKey(
        _map(vault, 'memberVaultKey'),
        memberPrivateKey,
      );
      discoveryKey = await _keys.openDiscoveryKey(
        _map(vault, 'discoveryKey'),
        vaultKey,
      );
      entryDek = await _envelopes.decrypt(
        profile: VaultAadProfile.entryKeyWrapper,
        envelope: wrapper,
        key: vaultKey,
        expected: VaultEnvelopeExpectations(
          aadContext: wrapper,
          minimumMemberKeyGeneration: wrapperGeneration,
        ),
      );
      if (entryDek.length != 32) throw const FormatException('Invalid DEK');

      final nextRevision = _increment(snapshot.entry, 'currentRevision');
      final nextIndexRevision = _increment(
        snapshot.entry,
        'memberIndexRevision',
      );
      final nextDiscoveryRevision = _increment(
        snapshot.entry,
        'agentDiscoveryRevisionHighWatermark',
      );
      var keyVersion = _int(snapshot.entry, 'currentKeyVersion');
      Map<String, dynamic>? newEntryKey;
      if (wrapperGeneration != generation) {
        if (keyVersion >= 0xffffffff) {
          throw const FormatException('Entry key version overflow');
        }
        keyVersion += 1;
        final wrappingKeyVersion = _int(epoch, 'vaultKeyVersion');
        final wrapperContext = <String, Object?>{
          'organizationId': organizationId,
          'vaultId': expected.vaultId,
          'entryId': expected.id,
          'wrapperRevision': '1',
          'keyVersion': keyVersion,
          'memberKeyGeneration': generation,
          'wrappingKeyVersion': wrappingKeyVersion,
          'header': {
            'protocolVersion': 2,
            'algorithmSuite': 1,
            'resourceKind': 2,
            'projectionKind': 8,
            'resourceRevision': '1',
            'keyVersion': keyVersion,
            'memberKeyGeneration': generation,
            'nonce': '',
          },
        };
        final encryptedWrapper = await _envelopes.encrypt(
          profile: VaultAadProfile.entryKeyWrapper,
          context: wrapperContext,
          plaintext: entryDek,
          key: vaultKey,
        );
        newEntryKey = {
          ...wrapperContext,
          'header': {
            ...wrapperContext['header']! as Map,
            'nonce': encryptedWrapper['nonce'],
          },
          'wrappedEntryDekByVk': encryptedWrapper['ciphertext'],
        };
      }
      final wireType = type.toWire();
      final canonicalContent = <String, dynamic>{...content, 'type': wireType};
      final previousPolicy = snapshot.secret['agentVisibilityPolicy'];
      if (previousPolicy is! Map || previousPolicy['fields'] is! Map) {
        throw const FormatException('Missing Agent visibility policy');
      }
      final policy = Map<String, dynamic>.from(previousPolicy);
      final policyFields = Map<String, dynamic>.from(
        previousPolicy['fields'] as Map,
      );
      policy['fields'] = policyFields;
      final memberSecret = <String, dynamic>{
        'schemaVersion': 1,
        'memberLabel': label,
        'agentLabel': snapshot.secret['agentLabel'] is String
            ? snapshot.secret['agentLabel']
            : label,
        if (description.isNotEmpty) 'description': description,
        if (icon.isNotEmpty) 'iconReference': icon,
        'entryType': wireType,
        'content': canonicalContent,
        'agentVisibilityPolicy': policy,
      };
      final memberIndex = <String, dynamic>{
        'memberLabel': label,
        'entryType': wireType,
        'searchFields': [
          label,
          if (description.isNotEmpty) description,
          if (type == EntryType.credential && content['username'] is String)
            content['username'],
          if (type == EntryType.credential && content['url'] is String)
            content['url'],
        ],
        if (icon.isNotEmpty) 'iconReference': icon,
      };
      final discoveryFields = <String, String>{};
      if (type == EntryType.credential) {
        final username = content['username'];
        if (policyFields['username'] == 'discovery' &&
            username is String &&
            username.isNotEmpty) {
          discoveryFields['username'] = username;
        }
        final url = content['url'];
        if (policyFields['urlDomain'] == 'discovery' && url is String) {
          final domain = _domain(url);
          if (domain != null) discoveryFields['urlDomain'] = domain;
        }
      }
      final interpreter = content['interpreter'];
      if (type == EntryType.script &&
          policyFields['interpreter'] == 'discovery' &&
          interpreter is String) {
        discoveryFields['interpreter'] = interpreter;
      }
      final discovery = <String, dynamic>{
        'schemaVersion': 1,
        'agentLabel': memberSecret['agentLabel'],
        'entryType': wireType,
        'capabilities': ['get', 'inject'],
        'fields': discoveryFields,
      };
      final common = <String, Object?>{
        'organizationId': organizationId,
        'vaultId': expected.vaultId,
        'entryId': expected.id,
      };
      Map<String, dynamic> header(
        int projection,
        int projectionKeyVersion,
        String resourceRevision,
      ) => {
        'protocolVersion': 2,
        'algorithmSuite': 1,
        'resourceKind': 2,
        'projectionKind': projection,
        'resourceRevision': resourceRevision,
        'keyVersion': projectionKeyVersion,
        'memberKeyGeneration': generation,
        'nonce': '',
      };
      Future<Map<String, dynamic>> projection({
        required VaultAadProfile profile,
        required VaultKdfPurpose purpose,
        required Map<String, dynamic> value,
        required Uint8List baseKey,
        required int projectionKind,
        required int projectionKeyVersion,
        required String revisionName,
        required String revision,
      }) async {
        final key = deriveVaultProjectionKey(
          baseKey,
          VaultKdfContext(
            purpose: purpose,
            resourceKind: 2,
            organizationId: organizationId,
            vaultId: expected.vaultId,
            entryId: expected.id,
            keyVersion: projectionKeyVersion,
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
          revisionName: revision,
          if (profile == VaultAadProfile.memberSecret) 'operation': 2,
          if (profile == VaultAadProfile.agentDiscovery)
            'vdkVersion': vdkVersion,
          'header': header(projectionKind, projectionKeyVersion, revision),
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

      final secretEnvelope = await projection(
        profile: VaultAadProfile.memberSecret,
        purpose: VaultKdfPurpose.memberSecret,
        value: memberSecret,
        baseKey: entryDek,
        projectionKind: 3,
        projectionKeyVersion: keyVersion,
        revisionName: 'revision',
        revision: nextRevision,
      );
      final indexEnvelope = await projection(
        profile: VaultAadProfile.memberIndex,
        purpose: VaultKdfPurpose.memberIndex,
        value: memberIndex,
        baseKey: entryDek,
        projectionKind: 2,
        projectionKeyVersion: keyVersion,
        revisionName: 'memberIndexRevision',
        revision: nextIndexRevision,
      );
      final discoveryEnvelope = await projection(
        profile: VaultAadProfile.agentDiscovery,
        purpose: VaultKdfPurpose.agentDiscovery,
        value: discovery,
        baseKey: discoveryKey,
        projectionKind: 4,
        projectionKeyVersion: vdkVersion,
        revisionName: 'agentDiscoveryRevision',
        revision: nextDiscoveryRevision,
      );
      final response = await _entries
          .updateCanonicalEntry(expected.vaultId, expected.id, {
            'baseRevision': snapshot.entry['currentRevision'],
            'newEntryKey': ?newEntryKey,
            'memberSecret': secretEnvelope,
            'memberIndex': indexEnvelope,
            'agentDiscoveryChanged': true,
            'agentDiscovery': discoveryEnvelope,
            'grantEnvelopes': <Object>[],
          });
      if (response.statusCode == 409) {
        throw const CanonicalEntryDetailException(
          CanonicalEntryDetailError.conflict,
        );
      }
      if (response.statusCode != 200) {
        throw const CanonicalEntryDetailException(
          CanonicalEntryDetailError.corrupt,
        );
      }
      final now = DateTime.now().toUtc();
      return EntryEntity(
        id: expected.id,
        vaultId: expected.vaultId,
        label: label,
        description: description.isEmpty ? null : description,
        icon: icon.isEmpty ? null : icon,
        type: type,
        createdAt: expected.createdAt,
        updatedAt: now,
      );
    } on CanonicalEntryDetailException {
      rethrow;
    } on DioException catch (error) {
      throw CanonicalEntryDetailException(_classifyDio(error));
    } on FormatException {
      throw const CanonicalEntryDetailException(
        CanonicalEntryDetailError.corrupt,
      );
    } finally {
      _wipe([vaultKey, discoveryKey, entryDek, ...derived, ...plaintexts]);
    }
  }

  void _validateScope(Map<String, dynamic> value, EntryEntity expected) {
    if (value['vaultId'] != expected.vaultId || value['id'] != expected.id) {
      throw const FormatException('Entry scope mismatch');
    }
    _map(value, 'entryKey');
    _map(value, 'memberSecret');
  }

  Map<String, dynamic> _decodeCanonicalObject(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: false);
    final decoded = jsonDecode(text);
    if (decoded is! Map || canonicalizeVaultJson(decoded) != text) {
      throw const FormatException('Non-canonical JSON');
    }
    return Map<String, dynamic>.from(decoded);
  }

  String _increment(Map<String, dynamic> value, String key) {
    final raw = value[key];
    if (raw is! String || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(raw)) {
      throw FormatException('$key must be a canonical integer string');
    }
    final parsed = BigInt.parse(raw);
    final maximum = (BigInt.one << 64) - BigInt.one;
    if (parsed >= maximum) throw FormatException('$key overflow');
    return (parsed + BigInt.one).toString();
  }

  int _int(Map<String, dynamic> value, String key) {
    final result = value[key];
    if (result is! int || result < 0) throw FormatException('$key invalid');
    return result;
  }

  Map<String, dynamic> _map(Map<String, dynamic> value, String key) {
    final nested = value[key];
    if (nested is! Map) throw FormatException('$key must be an object');
    return Map<String, dynamic>.from(nested);
  }

  String? _domain(String raw) {
    final normalized = raw.contains('://') ? raw : 'https://$raw';
    final host = Uri.tryParse(normalized)?.host.toLowerCase();
    return host == null || host.isEmpty ? null : host;
  }

  CanonicalEntryDetailError _classifyDio(DioException error) {
    if (error.response == null) return CanonicalEntryDetailError.network;
    return switch (error.response?.statusCode) {
      403 => CanonicalEntryDetailError.forbidden,
      404 => CanonicalEntryDetailError.notFound,
      409 => CanonicalEntryDetailError.conflict,
      _ => CanonicalEntryDetailError.corrupt,
    };
  }

  void _wipe(Iterable<Uint8List?> values) {
    for (final value in values) {
      value?.fillRange(0, value.length, 0);
    }
  }
}
