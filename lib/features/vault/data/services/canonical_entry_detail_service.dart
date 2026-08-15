import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/agent_visibility_policy.dart'
    hide AgentFieldAccess;
import '../../domain/entities/agent_visibility_policy.dart'
    as visibility
    show AgentFieldAccess;
import '../../domain/entities/member_index_entry.dart';
import '../../domain/entities/vault_plaintext.dart';
import '../../../grants/data/datasources/grants_remote_datasource.dart';
import '../../../grants/data/models/grant_model.dart';
import '../../../grants/domain/entities/grant.dart';
import '../datasources/entry_remote_datasource.dart';
import '../datasources/vault_remote_datasource.dart';
import 'vault_protocol/vault_protocol_aad.dart';
import 'vault_protocol/vault_protocol_bytes.dart';
import 'vault_protocol/vault_protocol_envelope_service.dart';
import 'vault_protocol/vault_protocol_kdf.dart';
import 'vault_protocol/vault_protocol_fingerprint.dart';
import 'vault_protocol/vault_protocol_signature_service.dart';
import 'vault_rotation_crypto_service.dart';
import 'agent_visibility_projector.dart';
import 'entry_v2_crypto_service.dart';
import 'vault_crypto_service.dart';

enum CanonicalEntryDetailError {
  conflict,
  corrupt,
  forbidden,
  notFound,
  network,
}

/// Sequential canonical decrypt session used only by local export.
class CanonicalEntryExportSession {
  CanonicalEntryExportSession._({
    required CanonicalEntryDetailService owner,
    required this.vaultId,
    required this.organizationId,
    required this.memberKeyGeneration,
    required Uint8List vaultKey,
  }) : _owner = owner,
       _vaultKey = vaultKey;

  final CanonicalEntryDetailService _owner;
  final String vaultId;
  final String organizationId;
  final int memberKeyGeneration;
  Uint8List? _vaultKey;

  Future<CanonicalEntrySnapshot> revealCurrent(
    MemberIndexEntry expected,
  ) async {
    final key = _vaultKey;
    if (key == null) throw StateError('Export session is closed');
    try {
      final entry = await _owner._entries.getCanonicalEntry(
        vaultId,
        expected.entryId,
      );
      if (entry['id'] != expected.entryId ||
          entry['vaultId'] != vaultId ||
          entry['organizationId'] != organizationId ||
          entry['currentRevision'] != expected.revision) {
        throw const FormatException('Entry head scope mismatch');
      }
      return await _open(
        entry: entry,
        wrapper: _owner._map(entry, 'entryKey'),
        secret: _owner._map(entry, 'memberSecret'),
        revision: expected.revision,
      );
    } on DioException catch (error) {
      throw CanonicalEntryDetailException(_owner._classifyDio(error));
    } on FormatException {
      throw const CanonicalEntryDetailException(
        CanonicalEntryDetailError.corrupt,
      );
    }
  }

  Future<CanonicalEntrySnapshot> revealHistory({
    required MemberIndexEntry expected,
    required Map<String, dynamic> historyItem,
  }) async {
    final key = _vaultKey;
    if (key == null) throw StateError('Export session is closed');
    try {
      final revision = historyItem['revision'];
      if (revision is! String) throw const FormatException('Missing revision');
      final wrapper = _owner._map(historyItem, 'entryKey');
      final secret = _owner._map(historyItem, 'memberSecret');
      for (final value in [wrapper, secret]) {
        if (value['organizationId'] != organizationId ||
            value['vaultId'] != vaultId ||
            value['entryId'] != expected.entryId) {
          throw const FormatException('Historical scope mismatch');
        }
      }
      return await _open(
        entry: <String, dynamic>{
          'id': expected.entryId,
          'vaultId': vaultId,
          'organizationId': organizationId,
        },
        wrapper: wrapper,
        secret: secret,
        revision: revision,
      );
    } on DioException catch (error) {
      throw CanonicalEntryDetailException(_owner._classifyDio(error));
    } on FormatException catch (error) {
      assert(() {
        throw StateError(error.message);
      }());
      throw const CanonicalEntryDetailException(
        CanonicalEntryDetailError.corrupt,
      );
    }
  }

  Future<CanonicalEntrySnapshot> _open({
    required Map<String, dynamic> entry,
    required Map<String, dynamic> wrapper,
    required Map<String, dynamic> secret,
    required String revision,
  }) async {
    final vaultKey = _vaultKey!;
    Uint8List? entryDek;
    Uint8List? secretKey;
    Uint8List? plaintext;
    try {
      if (_owner._entryV2 != null && wrapper['descriptor'] is Map) {
        _owner._validateCanonicalEnvelope(
          wrapper,
          entry,
          entry['id'] as String,
        );
        _owner._validateCanonicalEnvelope(
          secret,
          entry,
          entry['id'] as String,
          expectedRevision: revision,
        );
        final adapted = _owner._adaptCanonicalSecret(
          await _owner._entryV2.openMemberSecret(
            entryKey: wrapper,
            memberSecret: secret,
            vaultKey: vaultKey,
          ),
        );
        return CanonicalEntrySnapshot(
          entry: entry,
          secret: adapted,
          payload: Map<String, dynamic>.from(adapted['content'] as Map),
        );
      }
      final wrapperGeneration = _owner._int(wrapper, 'memberKeyGeneration');
      if (wrapperGeneration > memberKeyGeneration) {
        throw const FormatException('Entry key generation is from the future');
      }
      entryDek = await _owner._envelopes.decrypt(
        profile: VaultAadProfile.entryKeyWrapper,
        envelope: wrapper,
        key: vaultKey,
        expected: VaultEnvelopeExpectations(
          aadContext: wrapper,
          minimumMemberKeyGeneration: wrapperGeneration,
        ),
      );
      if (entryDek.length != 32) throw const FormatException('Invalid DEK');
      final header = _owner._map(secret, 'header');
      if (secret['revision'] != revision ||
          header['memberKeyGeneration'] != wrapperGeneration ||
          header['keyVersion'] != wrapper['keyVersion']) {
        throw const FormatException('MemberSecret revision mismatch');
      }
      secretKey = deriveVaultProjectionKey(
        entryDek,
        VaultKdfContext(
          purpose: VaultKdfPurpose.memberSecret,
          resourceKind: 2,
          organizationId: organizationId,
          vaultId: vaultId,
          entryId: entry['id']! as String,
          keyVersion: _owner._int(header, 'keyVersion'),
          memberKeyGeneration: wrapperGeneration,
        ),
      );
      plaintext = await _owner._envelopes.decrypt(
        profile: VaultAadProfile.memberSecret,
        envelope: secret,
        key: secretKey,
        expected: VaultEnvelopeExpectations(
          aadContext: secret,
          minimumMemberKeyGeneration: wrapperGeneration,
        ),
      );
      final value = _owner._decodeCanonicalObject(plaintext);
      final payload = value['content'];
      if (value['schemaVersion'] != 1 || payload is! Map) {
        throw const FormatException('Malformed MemberSecret');
      }
      return CanonicalEntrySnapshot(
        entry: entry,
        secret: value,
        payload: Map<String, dynamic>.from(payload),
      );
    } finally {
      _owner._wipe([entryDek, secretKey, plaintext]);
    }
  }

  void close() {
    _vaultKey?.fillRange(0, _vaultKey!.length, 0);
    _vaultKey = null;
  }
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

  void clear() {
    entry.clear();
    payload.clear();
    secret.clear();
  }
}

abstract interface class EntryArchiveRestorer {
  Future<void> restoreArchived({
    required String vaultId,
    required MemberIndexEntry archived,
    required Uint8List memberPrivateKey,
  });

  Future<void> restoreRecoverable({
    required String vaultId,
    required MemberIndexEntry entry,
    required Uint8List memberPrivateKey,
  });

  Future<void> purgeDeleted({required String vaultId, required String entryId});
}

/// A locally authenticated historical MemberSecret snapshot.
final class CanonicalEntryHistorySnapshot {
  CanonicalEntryHistorySnapshot({required this.secret, required this.payload});

  final Map<String, dynamic> secret;
  final Map<String, dynamic> payload;

  void clear() {
    payload.clear();
    secret.clear();
  }
}

/// Opens and replaces canonical Entry projections without a legacy fallback.
///
/// Plaintext and key material exist only in method-local memory and are wiped
/// in `finally` paths. The update is one optimistic backend transaction: a
/// new immutable MemberSecret revision and the matching MemberIndex and
/// AgentDiscovery heads either all advance or none do.
class CanonicalEntryDetailService implements EntryArchiveRestorer {
  CanonicalEntryDetailService({
    required EntryRemoteDatasource entries,
    required VaultRemoteDatasource vaults,
    required VaultRotationCryptoService keys,
    VaultCryptoService? vaultCrypto,
    required VaultEnvelopeCryptography envelopes,
    required GrantsRemoteDatasource grants,
    EntryV2CryptoService? entryV2,
  }) : _entries = entries,
       _vaults = vaults,
       _keys = keys,
       _vaultCrypto = vaultCrypto,
       _envelopes = envelopes,
       _grants = grants,
       _entryV2 = entryV2;

  final EntryRemoteDatasource _entries;
  final VaultRemoteDatasource _vaults;
  final VaultRotationCryptoService _keys;
  final VaultCryptoService? _vaultCrypto;
  final VaultEnvelopeCryptography _envelopes;
  final GrantsRemoteDatasource _grants;
  final EntryV2CryptoService? _entryV2;

  /// Opens the Vault key once for a bounded export. The returned session owns
  /// that key and must be closed in `finally`.
  Future<CanonicalEntryExportSession> beginExportSession({
    required String vaultId,
    required Uint8List memberPrivateKey,
  }) async {
    Uint8List? vaultKey;
    try {
      final vault = await _vaults.getEncryptedVault(vaultId);
      final organizationId = vault['organizationId'];
      if (organizationId is! String) {
        throw const FormatException('Missing Vault organization');
      }
      vaultKey = await _keys.openMemberVaultKey(
        _map(vault, 'memberVaultKey'),
        memberPrivateKey,
      );
      final session = CanonicalEntryExportSession._(
        owner: this,
        vaultId: vaultId,
        organizationId: organizationId,
        memberKeyGeneration: _int(vault, 'memberKeyGeneration'),
        vaultKey: vaultKey,
      );
      vaultKey = null;
      return session;
    } on DioException catch (error) {
      throw CanonicalEntryDetailException(_classifyDio(error));
    } on FormatException {
      throw const CanonicalEntryDetailException(
        CanonicalEntryDetailError.corrupt,
      );
    } finally {
      vaultKey?.fillRange(0, vaultKey.length, 0);
    }
  }

  /// Authenticates and decrypts exactly one version selected by the user.
  Future<CanonicalEntryHistorySnapshot> revealHistoryVersion({
    required EntryEntity expected,
    required Map<String, dynamic> historyItem,
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
      final secret = _map(historyItem, 'memberSecret');
      final wrapper = _map(historyItem, 'entryKey');
      if (_entryV2 != null && wrapper['descriptor'] is Map) {
        vaultKey = await _keys.openMemberVaultKey(
          _map(vault, 'memberVaultKey'),
          memberPrivateKey,
        );
        _validateCanonicalEnvelope(
          wrapper,
          entry,
          expected.id,
          expectedRevision: historyItem['entryKeyRevision']?.toString(),
        );
        _validateCanonicalEnvelope(
          secret,
          entry,
          expected.id,
          expectedRevision: historyItem['revision']?.toString(),
        );
        final adapted = _adaptCanonicalSecret(
          await _entryV2.openMemberSecret(
            entryKey: wrapper,
            memberSecret: secret,
            vaultKey: vaultKey,
          ),
        );
        return CanonicalEntryHistorySnapshot(
          secret: adapted,
          payload: Map<String, dynamic>.from(adapted['content'] as Map),
        );
      }
      final header = _map(secret, 'header');
      if (secret['organizationId'] != entry['organizationId'] ||
          secret['vaultId'] != expected.vaultId ||
          secret['entryId'] != expected.id ||
          secret['revision'] != historyItem['revision'] ||
          header['keyVersion'] != historyItem['keyVersion']) {
        throw const FormatException('History version scope mismatch');
      }
      if (wrapper['organizationId'] != entry['organizationId'] ||
          wrapper['vaultId'] != expected.vaultId ||
          wrapper['entryId'] != expected.id ||
          wrapper['keyVersion'] != historyItem['keyVersion']) {
        throw const FormatException('Historical Entry key scope mismatch');
      }
      final wrapperGeneration = _int(wrapper, 'memberKeyGeneration');
      vaultKey = await _keys.openMemberVaultKey(
        _map(vault, 'memberVaultKey'),
        memberPrivateKey,
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
          minimumMemberKeyGeneration: _int(header, 'memberKeyGeneration'),
        ),
      );
      final value = _decodeCanonicalObject(plaintext);
      final content = value['content'];
      if (value['schemaVersion'] != 1 || content is! Map) {
        throw const FormatException('Malformed historical MemberSecret');
      }
      return CanonicalEntryHistorySnapshot(
        secret: value,
        payload: Map<String, dynamic>.from(content),
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
      if (_entryV2 != null && wrapper['descriptor'] is Map) {
        final value = await _entryV2.openMemberSecret(
          entryKey: wrapper,
          memberSecret: _map(entry, 'memberSecret'),
          vaultKey: vaultKey,
        );
        final adapted = _adaptCanonicalSecret(value);
        final payload = adapted['content'];
        if (payload is! Map) {
          throw const FormatException('Malformed MemberSecret');
        }
        return CanonicalEntrySnapshot(
          entry: entry,
          secret: adapted,
          payload: Map<String, dynamic>.from(payload),
        );
      }
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

  Map<String, dynamic> _adaptCanonicalSecret(Map<String, dynamic> value) {
    if (value['schema'] != MemberSecret.schema ||
        value['content'] is! Map ||
        value['agentFieldAccess'] is! Map) {
      throw const FormatException('Malformed canonical MemberSecret');
    }
    final type = switch (value['entryType']) {
      'key' => EntryType.key.toWire(),
      'credential' => EntryType.credential.toWire(),
      'script' => EntryType.script.toWire(),
      'creditCard' => EntryType.creditCard.toWire(),
      _ => throw const FormatException('Unknown canonical Entry type'),
    };
    final policyFields = <String, dynamic>{};
    for (final field in (value['agentFieldAccess'] as Map).entries) {
      if (field.key is! String) {
        throw const FormatException('Invalid canonical field id');
      }
      final id = switch (field.key as String) {
        'memberLabel' || 'icon' || 'color' || 'entryType' => null,
        'key.value' => 'value',
        'credential.username' => 'username',
        'credential.password' => 'password',
        'credential.url' => 'url',
        'credential.urlDomain' => 'urlDomain',
        'credential.totp' => 'totp',
        'script.source' => 'script',
        'script.interpreter' => 'interpreter',
        'script.refs' => 'refs',
        'creditCard.cardholderName' => 'cardholderName',
        'creditCard.cardNumber' => 'cardNumber',
        'creditCard.expiryMonth' => 'expiryMonth',
        'creditCard.expiryYear' => 'expiryYear',
        'creditCard.securityCode' => 'securityCode',
        'creditCard.pin' => 'pin',
        'creditCard.billingAddress' => 'billingAddress',
        final String id when id.startsWith('custom:') => id.substring(7),
        final String id => id,
      };
      if (id != null) policyFields[id] = field.value;
    }
    return <String, dynamic>{
      'schemaVersion': 1,
      'entryType': type,
      'memberLabel': value['memberLabel'],
      'agentLabel': value['agentLabel'],
      'description': value['description'],
      'iconReference': switch (value['icon']) {
        {'kind': 'glyph', 'value': final String icon} => icon,
        {'kind': 'encryptedAsset', 'assetId': final String id} => 'asset:$id',
        {
          'kind': 'publicAsset',
          'assetId': final String id,
          'revision': final int revision,
          'url': final String url,
        } =>
          'public-asset:$id|$revision|${Uri.encodeComponent(url)}',
        _ => null,
      },
      'content': Map<String, dynamic>.from(value['content'] as Map),
      'agentVisibilityPolicy': {
        'discoverable': value['discoverable'],
        'fields': policyFields,
      },
    };
  }

  void _validateCanonicalEnvelope(
    Map<String, dynamic> envelope,
    Map<String, dynamic> entry,
    String entryId, {
    String? expectedRevision,
  }) {
    final descriptor = _map(envelope, 'descriptor');
    final scope = _map(descriptor, 'scope');
    if (scope['organizationId'] != entry['organizationId'] ||
        scope['vaultId'] != entry['vaultId'] ||
        scope['entryId'] != entryId ||
        (expectedRevision != null &&
            descriptor['resourceRevision'] != expectedRevision)) {
      throw const FormatException(
        'Canonical envelope scope or revision mismatch',
      );
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
    AgentVisibilityPolicy? agentVisibilityPolicy,
    String? agentLabel,
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
      final wrapperGeneration = wrapper['descriptor'] is Map
          ? _int(_map(wrapper, 'descriptor'), 'memberKeyGeneration')
          : _int(wrapper, 'memberKeyGeneration');
      if (wrapperGeneration > generation) {
        throw const FormatException('Entry key generation is from the future');
      }
      if (_entryV2 != null && wrapper['descriptor'] is Map) {
        final canonicalVaultCrypto = _vaultCrypto;
        if (canonicalVaultCrypto == null) {
          throw const FormatException('Missing canonical Vault cryptography');
        }
        final openedVault = await canonicalVaultCrypto.openVaultProjection(
          json: vault,
          memberPrivateKey: memberPrivateKey,
        );
        vaultKey = openedVault.vaultKey;
        discoveryKey = openedVault.vaultDiscoveryKey;
        if (discoveryKey == null) {
          throw const FormatException('Missing Vault discovery key');
        }
        return await _updateCanonicalV2(
          snapshot: snapshot,
          expected: expected,
          label: label,
          description: description,
          icon: icon,
          type: type,
          content: content,
          policyOverride: agentVisibilityPolicy,
          agentLabelOverride: agentLabel,
          organizationId: organizationId,
          generation: generation,
          epoch: epoch,
          vaultKey: vaultKey,
          discoveryKey: discoveryKey,
          wrapper: wrapper,
        );
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
      final parsedPreviousPolicy = AgentVisibilityPolicy.fromJson(
        type,
        Map<String, dynamic>.from(previousPolicy),
        content: snapshot.payload,
      );
      final policy = _policyForUpdatedContent(
        type,
        content,
        agentVisibilityPolicy ?? parsedPreviousPolicy,
      );
      final policyJson = policy.toJson();
      final memberSecret = <String, dynamic>{
        'schemaVersion': 1,
        'memberLabel': label,
        'agentLabel':
            agentLabel ??
            (snapshot.secret['agentLabel'] is String
                ? snapshot.secret['agentLabel']
                : label),
        if (description.isNotEmpty) 'description': description,
        if (icon.isNotEmpty) 'iconReference': icon,
        'entryType': wireType,
        'content': canonicalContent,
        'agentVisibilityPolicy': policyJson,
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
        if (type == EntryType.credential && content['url'] is String)
          'autofillDomains': [content['url']],
        if (icon.isNotEmpty) 'iconReference': icon,
      };
      final discovery = AgentVisibilityProjector.discovery(
        type: type,
        agentLabel: memberSecret['agentLabel'] as String,
        description: description,
        content: canonicalContent,
        policy: policy,
      );
      final previousDiscovery = AgentVisibilityProjector.discovery(
        type: type,
        agentLabel: snapshot.secret['agentLabel'] as String? ?? label,
        description: snapshot.secret['description'] as String? ?? '',
        content: snapshot.payload,
        policy: parsedPreviousPolicy,
      );
      final discoveryChanged =
          canonicalizeVaultJson(discovery) !=
          canonicalizeVaultJson(previousDiscovery);
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
      final discoveryEnvelope = discoveryChanged
          ? await projection(
              profile: VaultAadProfile.agentDiscovery,
              purpose: VaultKdfPurpose.agentDiscovery,
              value: discovery,
              baseKey: discoveryKey,
              projectionKind: 4,
              projectionKeyVersion: vdkVersion,
              revisionName: 'agentDiscoveryRevision',
              revision: _increment(
                snapshot.entry,
                'agentDiscoveryRevisionHighWatermark',
              ),
            )
          : null;
      final grantEnvelopes = await _refreshActiveGrants(
        organizationId: organizationId,
        vaultId: expected.vaultId,
        entryId: expected.id,
        entryRevision: nextRevision,
        memberKeyGeneration: generation,
        type: type,
        agentLabel: memberSecret['agentLabel'] as String,
        description: description,
        content: canonicalContent,
        policy: policy,
      );
      final response = await _entries
          .updateCanonicalEntry(expected.vaultId, expected.id, {
            'baseRevision': snapshot.entry['currentRevision'],
            'newEntryKey': ?newEntryKey,
            'memberSecret': secretEnvelope,
            'memberIndex': indexEnvelope,
            'agentDiscoveryChanged': discoveryChanged,
            'agentDiscovery': ?discoveryEnvelope,
            'grantEnvelopes': grantEnvelopes,
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

  Future<EntryEntity> _updateCanonicalV2({
    required CanonicalEntrySnapshot snapshot,
    required EntryEntity expected,
    required String label,
    required String description,
    required String icon,
    required EntryType type,
    required Map<String, dynamic> content,
    required AgentVisibilityPolicy? policyOverride,
    required String? agentLabelOverride,
    required String organizationId,
    required int generation,
    required Map<String, dynamic> epoch,
    required Uint8List vaultKey,
    required Uint8List discoveryKey,
    required Map<String, dynamic> wrapper,
  }) async {
    Uint8List? entryDek;
    try {
      final descriptor = _map(wrapper, 'descriptor');
      final wrapperGeneration = _int(descriptor, 'memberKeyGeneration');
      if (wrapperGeneration > generation) {
        throw const FormatException('Entry key generation is from the future');
      }
      entryDek = await _entryV2!.openEntryDek(
        entryKey: wrapper,
        vaultKey: vaultKey,
      );
      if (entryDek.length != 32) {
        throw const FormatException('Invalid Entry DEK');
      }
      final previousPolicyValue = snapshot.secret['agentVisibilityPolicy'];
      if (previousPolicyValue is! Map) {
        throw const FormatException('Missing Agent visibility policy');
      }
      final previousPolicy = AgentVisibilityPolicy.fromJson(
        type,
        Map<String, dynamic>.from(previousPolicyValue),
        content: snapshot.payload,
      );
      final policy = _policyForUpdatedContent(
        type,
        content,
        policyOverride ?? previousPolicy,
      );
      final nextAgentLabel =
          agentLabelOverride ??
          snapshot.secret['agentLabel'] as String? ??
          label;
      final canonicalSecret = _canonicalSecret(
        type: type,
        label: label,
        agentLabel: nextAgentLabel,
        description: description,
        icon: icon,
        content: content,
        policy: policy,
      );
      final previousDiscovery = AgentVisibilityProjector.discovery(
        type: type,
        agentLabel: snapshot.secret['agentLabel'] as String? ?? label,
        description: snapshot.secret['description'] as String? ?? '',
        content: snapshot.payload,
        policy: previousPolicy,
      );
      final nextDiscovery = VaultPlaintextProjector.agentDiscovery(
        canonicalSecret,
      );
      final discoveryChanged =
          canonicalizeVaultJson(
            nextDiscovery as Object? ?? const <String, Object?>{},
          ) !=
          canonicalizeVaultJson(previousDiscovery);
      final nextRevision = int.parse(
        _increment(snapshot.entry, 'currentRevision'),
      );
      final nextIndexRevision = int.parse(
        _increment(snapshot.entry, 'memberIndexRevision'),
      );
      final nextDiscoveryRevision = int.parse(
        _increment(snapshot.entry, 'agentDiscoveryRevisionHighWatermark'),
      );
      var keyVersion = _int(snapshot.entry, 'currentKeyVersion');
      final rewrap = wrapperGeneration != generation;
      if (rewrap) keyVersion = _incrementInt(keyVersion, 'entryKeyVersion');
      final bundle = await _entryV2.seal(
        organizationId: organizationId,
        vaultId: expected.vaultId,
        entryId: expected.id,
        revision: nextRevision,
        entryKeyRevision:
            int.parse(descriptor['resourceRevision'] as String) +
            (rewrap ? 1 : 0),
        memberIndexRevision: nextIndexRevision,
        agentDiscoveryRevision: nextDiscoveryRevision,
        entryKeyVersion: keyVersion,
        vaultKeyVersion: _int(epoch, 'vaultKeyVersion'),
        vdkVersion: _int(epoch, 'vdkVersion'),
        memberKeyGeneration: generation,
        operation: 2,
        secret: canonicalSecret,
        vaultKey: vaultKey,
        vaultDiscoveryKey: discoveryKey,
        existingEntryDek: entryDek,
      );
      final grantEnvelopes = await _refreshActiveGrantsV2(
        organizationId: organizationId,
        vaultId: expected.vaultId,
        entryId: expected.id,
        entryRevision: nextRevision,
        memberKeyGeneration: generation,
        secret: canonicalSecret,
      );
      final response = await _entries
          .updateCanonicalEntry(expected.vaultId, expected.id, {
            'baseRevision': snapshot.entry['currentRevision'],
            if (rewrap) 'newEntryKey': bundle.entryKey,
            'memberSecret': bundle.memberSecret,
            'memberIndex': bundle.memberIndex,
            'agentDiscoveryChanged': discoveryChanged,
            if (discoveryChanged) 'agentDiscovery': bundle.agentDiscovery,
            'grantEnvelopes': grantEnvelopes,
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
      return EntryEntity(
        id: expected.id,
        vaultId: expected.vaultId,
        label: label,
        description: description.isEmpty ? null : description,
        icon: icon.isEmpty ? null : icon,
        type: type,
        createdAt: expected.createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
    } finally {
      entryDek?.fillRange(0, entryDek.length, 0);
    }
  }

  /// Restores one Archived Entry by appending an immutable Restored revision.
  ///
  /// The prepared encrypted request is retained for one transport retry so an
  /// ambiguous connection failure repeats byte-identical envelopes. No local
  /// MemberIndex head is fabricated; callers reconcile the committed head via
  /// the subsequent member delta.
  @override
  Future<void> restoreArchived({
    required String vaultId,
    required MemberIndexEntry archived,
    required Uint8List memberPrivateKey,
  }) => restoreRecoverable(
    vaultId: vaultId,
    entry: archived,
    memberPrivateKey: memberPrivateKey,
  );

  @override
  Future<void> restoreRecoverable({
    required String vaultId,
    required MemberIndexEntry entry,
    required Uint8List memberPrivateKey,
  }) async {
    if ((entry.state != MemberEntryState.archived &&
            entry.state != MemberEntryState.deleted) ||
        entry.corrupt) {
      throw const CanonicalEntryDetailException(
        CanonicalEntryDetailError.corrupt,
      );
    }
    final archived = entry;
    final expected = EntryEntity(
      id: archived.entryId,
      vaultId: vaultId,
      label: archived.memberLabel,
      icon: archived.iconReference,
      type: EntryTypeExtension.fromWire(archived.entryType),
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lifecycleState: MemberEntryState.archived,
      currentRevision: archived.revision,
    );
    CanonicalEntrySnapshot? snapshot;
    Uint8List? vaultKey;
    Uint8List? discoveryKey;
    Uint8List? entryDek;
    final derived = <Uint8List>[];
    final plaintexts = <Uint8List>[];
    try {
      snapshot = await reveal(
        expected: expected,
        memberPrivateKey: memberPrivateKey,
      );
      final expectedState = entry.state == MemberEntryState.archived ? 2 : 3;
      final state = snapshot.entry['state'];
      if (state != expectedState &&
          state != entry.state.name &&
          state !=
              '${entry.state.name[0].toUpperCase()}${entry.state.name.substring(1)}') {
        throw const FormatException('Entry lifecycle state mismatch');
      }
      final vault = await _vaults.getEncryptedVault(vaultId);
      final organizationId = snapshot.entry['organizationId'];
      if (organizationId is! String ||
          vault['organizationId'] != organizationId) {
        throw const FormatException('Vault organization mismatch');
      }
      final generation = _int(vault, 'memberKeyGeneration');
      final epoch = _map(vault, 'currentKeyEpoch');
      final vdkVersion = _int(epoch, 'vdkVersion');
      final wrapper = _map(snapshot.entry, 'entryKey');
      final wrapperGeneration = wrapper['descriptor'] is Map
          ? _int(_map(wrapper, 'descriptor'), 'memberKeyGeneration')
          : _int(wrapper, 'memberKeyGeneration');
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
      if (_entryV2 != null && wrapper['descriptor'] is Map) {
        await _restoreCanonicalV2(
          snapshot: snapshot,
          archived: archived,
          vaultId: vaultId,
          organizationId: organizationId,
          generation: generation,
          epoch: epoch,
          vaultKey: vaultKey,
          discoveryKey: discoveryKey,
          wrapper: wrapper,
        );
        return;
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

      var keyVersion = _int(snapshot.entry, 'currentKeyVersion');
      Map<String, dynamic>? newEntryKey;
      if (wrapperGeneration != generation) {
        if (keyVersion >= 0xffffffff) {
          throw const FormatException('Entry key version overflow');
        }
        keyVersion += 1;
        final wrapperContext = <String, Object?>{
          'organizationId': organizationId,
          'vaultId': vaultId,
          'entryId': archived.entryId,
          'wrapperRevision': '1',
          'keyVersion': keyVersion,
          'memberKeyGeneration': generation,
          'wrappingKeyVersion': _int(epoch, 'vaultKeyVersion'),
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
        final encrypted = await _envelopes.encrypt(
          profile: VaultAadProfile.entryKeyWrapper,
          context: wrapperContext,
          plaintext: entryDek,
          key: vaultKey,
        );
        newEntryKey = {
          ...wrapperContext,
          'header': {
            ...wrapperContext['header']! as Map,
            'nonce': encrypted['nonce'],
          },
          'wrappedEntryDekByVk': encrypted['ciphertext'],
        };
      }

      final nextRevision = _increment(snapshot.entry, 'currentRevision');
      final nextIndexRevision = _increment(
        snapshot.entry,
        'memberIndexRevision',
      );
      final nextDiscoveryRevision = _increment(
        snapshot.entry,
        'agentDiscoveryRevisionHighWatermark',
      );
      final secret = Map<String, dynamic>.from(snapshot.secret);
      final policyValue = secret['agentVisibilityPolicy'];
      if (policyValue is! Map) {
        throw const FormatException('Missing Agent visibility policy');
      }
      final type = EntryTypeExtension.fromWire(archived.entryType);
      final policy = AgentVisibilityPolicy.fromJson(
        type,
        Map<String, dynamic>.from(policyValue),
        content: snapshot.payload,
      );
      final description = secret['description'] as String? ?? '';
      final agentLabel =
          secret['agentLabel'] as String? ?? archived.memberLabel;
      final discovery = AgentVisibilityProjector.discovery(
        type: type,
        agentLabel: agentLabel,
        description: description,
        content: snapshot.payload,
        policy: policy,
      );
      final memberIndex = <String, dynamic>{
        'memberLabel': archived.memberLabel,
        'entryType': archived.entryType,
        'searchFields': List<String>.from(archived.searchFields),
        if (archived.autofillDomains.isNotEmpty)
          'autofillDomains': List<String>.from(archived.autofillDomains),
        'iconReference': ?archived.iconReference,
      };
      final common = <String, Object?>{
        'organizationId': organizationId,
        'vaultId': vaultId,
        'entryId': archived.entryId,
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
            vaultId: vaultId,
            entryId: archived.entryId,
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
          if (profile == VaultAadProfile.memberSecret) 'operation': 4,
          if (profile == VaultAadProfile.agentDiscovery)
            'vdkVersion': vdkVersion,
          'header': {
            'protocolVersion': 2,
            'algorithmSuite': 1,
            'resourceKind': 2,
            'projectionKind': projectionKind,
            'resourceRevision': revision,
            'keyVersion': projectionKeyVersion,
            'memberKeyGeneration': generation,
            'nonce': '',
          },
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

      final request = <String, dynamic>{
        'baseRevision': snapshot.entry['currentRevision'],
        'newEntryKey': ?newEntryKey,
        'memberSecret': await projection(
          profile: VaultAadProfile.memberSecret,
          purpose: VaultKdfPurpose.memberSecret,
          value: secret,
          baseKey: entryDek,
          projectionKind: 3,
          projectionKeyVersion: keyVersion,
          revisionName: 'revision',
          revision: nextRevision,
        ),
        'memberIndex': await projection(
          profile: VaultAadProfile.memberIndex,
          purpose: VaultKdfPurpose.memberIndex,
          value: memberIndex,
          baseKey: entryDek,
          projectionKind: 2,
          projectionKeyVersion: keyVersion,
          revisionName: 'memberIndexRevision',
          revision: nextIndexRevision,
        ),
        'agentDiscovery': await projection(
          profile: VaultAadProfile.agentDiscovery,
          purpose: VaultKdfPurpose.agentDiscovery,
          value: discovery,
          baseKey: discoveryKey,
          projectionKind: 4,
          projectionKeyVersion: vdkVersion,
          revisionName: 'agentDiscoveryRevision',
          revision: nextDiscoveryRevision,
        ),
      };
      Response<Map<String, dynamic>>? response;
      for (var attempt = 0; attempt < 2; attempt += 1) {
        try {
          response = await _entries.restoreCanonicalEntry(
            vaultId,
            archived.entryId,
            request,
          );
          break;
        } on DioException catch (error) {
          if (attempt == 1 || error.response != null) rethrow;
        }
      }
      if (response?.statusCode == 409) {
        throw const CanonicalEntryDetailException(
          CanonicalEntryDetailError.conflict,
        );
      }
      if (response?.statusCode != 200) {
        throw const CanonicalEntryDetailException(
          CanonicalEntryDetailError.corrupt,
        );
      }
    } on CanonicalEntryDetailException {
      rethrow;
    } on DioException catch (error) {
      throw CanonicalEntryDetailException(_classifyDio(error));
    } on FormatException {
      throw const CanonicalEntryDetailException(
        CanonicalEntryDetailError.corrupt,
      );
    } finally {
      snapshot?.clear();
      _wipe([vaultKey, discoveryKey, entryDek, ...derived, ...plaintexts]);
    }
  }

  Future<void> _restoreCanonicalV2({
    required CanonicalEntrySnapshot snapshot,
    required MemberIndexEntry archived,
    required String vaultId,
    required String organizationId,
    required int generation,
    required Map<String, dynamic> epoch,
    required Uint8List vaultKey,
    required Uint8List discoveryKey,
    required Map<String, dynamic> wrapper,
  }) async {
    Uint8List? entryDek;
    try {
      final descriptor = _map(wrapper, 'descriptor');
      final wrapperGeneration = _int(descriptor, 'memberKeyGeneration');
      if (wrapperGeneration > generation) {
        throw const FormatException('Entry key generation is from the future');
      }
      entryDek = await _entryV2!.openEntryDek(
        entryKey: wrapper,
        vaultKey: vaultKey,
      );
      if (entryDek.length != 32) {
        throw const FormatException('Invalid Entry DEK');
      }
      final type = EntryTypeExtension.fromWire(archived.entryType);
      final policyValue = snapshot.secret['agentVisibilityPolicy'];
      if (policyValue is! Map) {
        throw const FormatException('Missing Agent visibility policy');
      }
      final policy = AgentVisibilityPolicy.fromJson(
        type,
        Map<String, dynamic>.from(policyValue),
        content: snapshot.payload,
      );
      final secret = _canonicalSecret(
        type: type,
        label: archived.memberLabel,
        agentLabel:
            snapshot.secret['agentLabel'] as String? ?? archived.memberLabel,
        description: snapshot.secret['description'] as String? ?? '',
        icon: archived.iconReference ?? '',
        content: snapshot.payload,
        policy: policy,
      );
      final nextRevision = int.parse(
        _increment(snapshot.entry, 'currentRevision'),
      );
      final nextIndexRevision = int.parse(
        _increment(snapshot.entry, 'memberIndexRevision'),
      );
      final nextDiscoveryRevision = int.parse(
        _increment(snapshot.entry, 'agentDiscoveryRevisionHighWatermark'),
      );
      var keyVersion = _int(snapshot.entry, 'currentKeyVersion');
      final rewrap = wrapperGeneration != generation;
      if (rewrap) keyVersion = _incrementInt(keyVersion, 'entryKeyVersion');
      final bundle = await _entryV2.seal(
        organizationId: organizationId,
        vaultId: vaultId,
        entryId: archived.entryId,
        revision: nextRevision,
        entryKeyRevision:
            int.parse(descriptor['resourceRevision'] as String) +
            (rewrap ? 1 : 0),
        memberIndexRevision: nextIndexRevision,
        agentDiscoveryRevision: nextDiscoveryRevision,
        entryKeyVersion: keyVersion,
        vaultKeyVersion: _int(epoch, 'vaultKeyVersion'),
        vdkVersion: _int(epoch, 'vdkVersion'),
        memberKeyGeneration: generation,
        operation: 4,
        secret: secret,
        vaultKey: vaultKey,
        vaultDiscoveryKey: discoveryKey,
        existingEntryDek: entryDek,
      );
      final grants = await _refreshActiveGrantsV2(
        organizationId: organizationId,
        vaultId: vaultId,
        entryId: archived.entryId,
        entryRevision: nextRevision,
        memberKeyGeneration: generation,
        secret: secret,
      );
      final request = <String, dynamic>{
        'baseRevision': snapshot.entry['currentRevision'],
        if (rewrap) 'newEntryKey': bundle.entryKey,
        'memberSecret': bundle.memberSecret,
        'memberIndex': bundle.memberIndex,
        'agentDiscovery': bundle.agentDiscovery,
        'grantEnvelopes': grants,
      };
      Response<Map<String, dynamic>>? response;
      for (var attempt = 0; attempt < 2; attempt += 1) {
        try {
          response = await _entries.restoreCanonicalEntry(
            vaultId,
            archived.entryId,
            request,
          );
          break;
        } on DioException catch (error) {
          if (attempt == 1 || error.response != null) rethrow;
        }
      }
      if (response?.statusCode == 409) {
        throw const CanonicalEntryDetailException(
          CanonicalEntryDetailError.conflict,
        );
      }
      if (response?.statusCode != 200) {
        throw const CanonicalEntryDetailException(
          CanonicalEntryDetailError.corrupt,
        );
      }
    } finally {
      entryDek?.fillRange(0, entryDek.length, 0);
    }
  }

  @override
  Future<void> purgeDeleted({
    required String vaultId,
    required String entryId,
  }) async {
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        final response = await _entries.destroyEntry(vaultId, entryId);
        if (response.statusCode == 204 || response.statusCode == 404) return;
        if (response.statusCode == 409) {
          throw const CanonicalEntryDetailException(
            CanonicalEntryDetailError.conflict,
          );
        }
        throw const CanonicalEntryDetailException(
          CanonicalEntryDetailError.corrupt,
        );
      } on DioException catch (error) {
        if (attempt == 1 || error.response != null) {
          throw CanonicalEntryDetailException(_classifyDio(error));
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> _refreshActiveGrants({
    required String organizationId,
    required String vaultId,
    required String entryId,
    required String entryRevision,
    required int memberKeyGeneration,
    required EntryType type,
    required String agentLabel,
    required String description,
    required Map<String, dynamic> content,
    required AgentVisibilityPolicy policy,
  }) async {
    final active = <GrantModel>[];
    final seenCursors = <String>{};
    String? cursor;
    do {
      final page = await _grants.listGrants(
        vaultId,
        status: 'active',
        cursor: cursor,
        pageSize: 100,
      );
      active.addAll(page.grants);
      if (active.length > 1000) {
        throw const FormatException('Active grant refresh exceeds limit');
      }
      cursor = page.nextCursor;
      if (cursor != null && !seenCursors.add(cursor)) {
        throw const FormatException('Repeated active grant cursor');
      }
    } while (cursor != null);

    final result = <Map<String, dynamic>>[];
    for (final model in active) {
      final grant = model.toEntity();
      final scopes = grant.entryScopes
          .where((scope) => scope.entryId == entryId)
          .toList(growable: false);
      if (scopes.isEmpty) continue;
      if (scopes.length != 1 ||
          grant.agentPublicKey == null ||
          grant.agentPublicKey!.isEmpty ||
          grant.recipientAgentKeyVersion == null) {
        throw const FormatException('Incomplete active grant metadata');
      }
      result.add(
        await _refreshGrant(
          organizationId: organizationId,
          grant: grant,
          scope: scopes.single,
          entryRevision: entryRevision,
          memberKeyGeneration: memberKeyGeneration,
          type: type,
          agentLabel: agentLabel,
          description: description,
          content: content,
          policy: policy,
        ),
      );
    }
    return result;
  }

  MemberSecret _canonicalSecret({
    required EntryType type,
    required String label,
    required String agentLabel,
    required String description,
    required String icon,
    required Map<String, dynamic> content,
    required AgentVisibilityPolicy policy,
  }) {
    final custom = (content['fields'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (field) => VaultCustomField(
            id: field['id'] as String,
            label: field['label'] as String? ?? '',
            kind: field['type'] as String,
            value: field['value'],
            includeInMemberIndex: field['agentVisible'] == true,
          ),
        )
        .toList(growable: false);
    final body = switch (type) {
      EntryType.key => KeySecretContent(
        value: content['value'] as String,
        notes: content['notes'] as String?,
        customFields: custom,
      ),
      EntryType.credential => CredentialSecretContent(
        username: content['username'] as String,
        password: content['password'] as String,
        url: content['url'] as String?,
        urlDomain: _domain(content['url'] as String? ?? ''),
        totp: content['totp'] is Map
            ? Map<String, Object?>.from(content['totp'] as Map)
            : null,
        notes: content['notes'] as String?,
        customFields: custom,
      ),
      EntryType.script => ScriptSecretContent(
        source: content['script'] as String,
        interpreter: content['interpreter'] as String,
        refs: (content['refs'] as List)
            .map((value) => Map<String, Object?>.from(value as Map))
            .toList(),
        notes: content['notes'] as String?,
        customFields: custom,
      ),
      EntryType.creditCard => CreditCardSecretContent(
        cardholderName: content['cardholderName'] as String,
        cardNumber: content['cardNumber'] as String,
        expiryMonth: content['expiryMonth'] as String,
        expiryYear: content['expiryYear'] as String,
        securityCode: content['securityCode'] as String,
        pin: content['pin'] as String?,
        billingAddress: content['billingAddress'] as String?,
        notes: content['notes'] as String?,
        customFields: custom,
      ),
    };
    String canonicalId(String id) => switch ((type, id)) {
      (EntryType.key, 'value') => 'key.value',
      (EntryType.credential, 'username') => 'credential.username',
      (EntryType.credential, 'password') => 'credential.password',
      (EntryType.credential, 'url') => 'credential.url',
      (EntryType.credential, 'urlDomain') => 'credential.urlDomain',
      (EntryType.credential, 'totp') => 'credential.totp',
      (EntryType.script, 'script') => 'script.source',
      (EntryType.script, 'interpreter') => 'script.interpreter',
      (EntryType.script, 'refs') => 'script.refs',
      (EntryType.creditCard, final value)
          when const {
            'cardholderName',
            'cardNumber',
            'expiryMonth',
            'expiryYear',
            'securityCode',
            'pin',
            'billingAddress',
          }.contains(value) =>
        'creditCard.$value',
      (_, final value) when custom.any((field) => field.id == value) =>
        'custom:$value',
      _ => id,
    };
    final access = <String, AgentFieldAccess>{
      for (final item in policy.fields.entries)
        canonicalId(item.key): AgentFieldAccess.values.byName(
          item.value.wireName,
        ),
      'memberLabel': AgentFieldAccess.never,
      'icon': AgentFieldAccess.never,
      'color': AgentFieldAccess.never,
      'entryType': AgentFieldAccess.discovery,
      'agentLabel': AgentFieldAccess.discovery,
      'description': AgentFieldAccess.never,
    };
    for (final id in body.fieldValues().keys) {
      access.putIfAbsent(
        id,
        () => id == 'credential.totp'
            ? AgentFieldAccess.onGrantDerived
            : id.startsWith('script.') && id != 'script.interpreter'
            ? AgentFieldAccess.onGrantRuntime
            : AgentFieldAccess.onGrantValue,
      );
    }
    for (final field in custom) {
      access.putIfAbsent(field.fieldId, () => AgentFieldAccess.never);
    }
    return MemberSecret(
      entryType: VaultEntryType.values[type.index],
      memberLabel: label,
      agentLabel: agentLabel,
      description: description.isEmpty ? null : description,
      icon: VaultPlaintextIcon.fromReference(icon),
      color: null,
      discoverable: policy.discoverable,
      content: body,
      agentFieldAccess: access,
    );
  }

  String? _domain(String raw) {
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    return uri == null || uri.host.isEmpty ? null : uri.host.toLowerCase();
  }

  Future<List<Map<String, dynamic>>> _refreshActiveGrantsV2({
    required String organizationId,
    required String vaultId,
    required String entryId,
    required int entryRevision,
    required int memberKeyGeneration,
    required MemberSecret secret,
  }) async {
    final active = <GrantModel>[];
    String? cursor;
    final seen = <String>{};
    do {
      final page = await _grants.listGrants(
        vaultId,
        status: 'active',
        cursor: cursor,
        pageSize: 100,
      );
      active.addAll(page.grants);
      if (active.length > 1000) {
        throw const FormatException('Active grant refresh exceeds limit');
      }
      cursor = page.nextCursor;
      if (cursor != null && !seen.add(cursor)) {
        throw const FormatException('Repeated active grant cursor');
      }
    } while (cursor != null);
    final result = <Map<String, dynamic>>[];
    for (final model in active) {
      final grant = model.toEntity();
      final scopes = grant.entryScopes
          .where((scope) => scope.entryId == entryId)
          .toList();
      if (scopes.isEmpty) continue;
      if (scopes.length != 1 ||
          grant.agentPublicKey == null ||
          grant.recipientAgentKeyVersion == null) {
        throw const FormatException('Incomplete active grant metadata');
      }
      final scope = scopes.single;
      final recipient = Uint8List.fromList(
        base64.decode(grant.agentPublicKey!),
      );
      try {
        final allowed = secret.agentFieldAccess.entries
            .where(
              (item) =>
                  item.value == AgentFieldAccess.onGrantValue ||
                  item.value == AgentFieldAccess.onGrantDerived ||
                  item.value == AgentFieldAccess.onGrantRuntime,
            )
            .map((item) => item.key)
            .toSet();
        final fields = scope.fieldIds
            .map((id) => _canonicalGrantFieldId(secret.entryType, id))
            .where(allowed.contains)
            .toList();
        if (fields.length != scope.fieldIds.length || fields.isEmpty) {
          throw const FormatException('Grant scope exceeds policy');
        }
        final remaining = grant.queryLimit == null
            ? null
            : grant.queryLimit! - (grant.queryCount ?? 0);
        if (remaining != null && remaining <= 0) {
          throw const FormatException('Active grant has no remaining uses');
        }
        final agentId = grant.agentId;
        if (agentId == null) {
          throw const FormatException('Active grant has no Agent principal');
        }
        final envelope = await _entryV2!.sealGrant(
          organizationId: organizationId,
          vaultId: vaultId,
          entryId: entryId,
          grantId: grant.id,
          agentId: agentId,
          entryRevision: entryRevision,
          memberKeyGeneration: memberKeyGeneration,
          agentPublicKey: recipient,
          recipientKeyVersion: grant.recipientAgentKeyVersion!,
          approvedMethods: _methodBits(grant.methods),
          deliveryPolicy: 0,
          fieldIds: fields,
          grantPayload: VaultPlaintextProjector.grantPayload(
            secret,
            fields.toSet(),
          ),
          grantEnvelopeRevision: int.parse(
            _incrementValue(
              scope.grantEnvelopeRevision,
              'grantEnvelopeRevision',
            ),
          ),
          grantKeyVersion: _incrementInt(
            scope.grantKeyVersion,
            'grantKeyVersion',
          ),
          expiresAt: grant.expiresAt,
          remainingUses: remaining,
        );
        result.add(Map<String, dynamic>.from(envelope));
      } finally {
        recipient.fillRange(0, recipient.length, 0);
      }
    }
    return result;
  }

  String _canonicalGrantFieldId(VaultEntryType type, String id) => switch ((
    type,
    id,
  )) {
    (VaultEntryType.key, 'value') => 'key.value',
    (VaultEntryType.credential, 'username') => 'credential.username',
    (VaultEntryType.credential, 'password') => 'credential.password',
    (VaultEntryType.credential, 'url') => 'credential.url',
    (VaultEntryType.credential, 'urlDomain') => 'credential.urlDomain',
    (VaultEntryType.credential, 'totp') => 'credential.totp',
    (VaultEntryType.script, 'script') => 'script.source',
    (VaultEntryType.script, 'interpreter') => 'script.interpreter',
    (VaultEntryType.script, 'refs') => 'script.refs',
    (VaultEntryType.creditCard, final value)
        when const {
          'cardholderName',
          'cardNumber',
          'expiryMonth',
          'expiryYear',
          'securityCode',
          'pin',
          'billingAddress',
        }.contains(value) =>
      'creditCard.$value',
    (_, final value)
        when value == 'notes' ||
            value == 'description' ||
            value == 'agentLabel' ||
            value.contains('.') =>
      value,
    (_, final value) => value.startsWith('custom:') ? value : 'custom:$value',
  };

  Future<Map<String, dynamic>> _refreshGrant({
    required String organizationId,
    required Grant grant,
    required GrantEntryScope scope,
    required String entryRevision,
    required int memberKeyGeneration,
    required EntryType type,
    required String agentLabel,
    required String description,
    required Map<String, dynamic> content,
    required AgentVisibilityPolicy policy,
  }) async {
    Uint8List? grantKey;
    Uint8List? recipientKey;
    Uint8List? fingerprint;
    Uint8List? plaintext;
    Uint8List? wrappedKey;
    try {
      final envelopeRevision = _incrementValue(
        scope.grantEnvelopeRevision,
        'grantEnvelopeRevision',
      );
      final grantKeyVersion = _incrementInt(
        scope.grantKeyVersion,
        'grantKeyVersion',
      );
      final recipientKeyVersion = grant.recipientAgentKeyVersion!;
      try {
        recipientKey = Uint8List.fromList(base64.decode(grant.agentPublicKey!));
      } on FormatException {
        throw const FormatException('Invalid Agent public key');
      }
      if (recipientKey.length != 32) {
        throw const FormatException('Invalid Agent public key');
      }
      fingerprint = vaultPublicKeyFingerprint(
        VaultPublicKeyKind.agentX25519,
        recipientKey,
      );
      final fingerprintWire = VaultProtocolBytes.base64UrlEncode(fingerprint);
      final approvedMethods = _methodBits(grant.methods);
      final remainingUses = grant.queryLimit == null
          ? null
          : grant.queryLimit! - (grant.queryCount ?? 0);
      if (remainingUses != null && remainingUses <= 0) {
        throw const FormatException('Active grant has no remaining uses');
      }
      final expiresAt = grant.expiresAt == null
          ? null
          : _canonicalInstant(grant.expiresAt!);
      final approvedFieldIds = scope.fieldIds;
      if (approvedFieldIds.isEmpty) {
        throw const FormatException('Entry has no grantable fields');
      }
      final payload = AgentVisibilityProjector.grantPayload(
        type: type,
        agentLabel: agentLabel,
        description: description,
        content: content,
        policy: policy,
        approvedFieldIds: approvedFieldIds,
      );
      plaintext = VaultProtocolBytes.utf8Encode(canonicalizeVaultJson(payload));
      grantKey = await _envelopes.randomKey();
      final context = <String, Object?>{
        'organizationId': organizationId,
        'vaultId': grant.vaultId,
        'entryId': scope.entryId,
        'grantId': grant.id,
        'agentId': grant.agentId,
        'grantEnvelopeRevision': envelopeRevision,
        'entryRevision': entryRevision,
        'grantKeyVersion': grantKeyVersion,
        'approvedMethods': approvedMethods,
        'expiresAt': ?expiresAt,
        'useLimit': ?remainingUses,
        'recipientAgentKeyVersion': recipientKeyVersion,
        'recipientAgentKeyFingerprint': fingerprintWire,
        'header': {
          'protocolVersion': 2,
          'algorithmSuite': 1,
          'resourceKind': 4,
          'projectionKind': 6,
          'resourceRevision': envelopeRevision,
          'keyVersion': grantKeyVersion,
          'memberKeyGeneration': memberKeyGeneration,
          'nonce': '',
        },
      };
      final encrypted = await _envelopes.encrypt(
        profile: VaultAadProfile.grantPayload,
        context: context,
        plaintext: plaintext,
        key: grantKey,
      );
      wrappedKey = await _envelopes.sealPackage(
        packageBytes: grantKey,
        recipientPublicKey: recipientKey,
      );
      return {
        'organizationId': organizationId,
        'vaultId': grant.vaultId,
        'grantId': grant.id,
        'entryId': scope.entryId,
        'grantEnvelopeRevision': envelopeRevision,
        'entryRevision': entryRevision,
        'protocolVersion': 2,
        'algorithmSuite': 1,
        'grantKeyVersion': grantKeyVersion,
        'memberKeyGeneration': memberKeyGeneration,
        'recipientAgentKeyVersion': recipientKeyVersion,
        'ciphertext': encrypted['ciphertext'],
        'nonce': encrypted['nonce'],
        'agentWrappedGrantDek': VaultProtocolBytes.base64UrlEncode(wrappedKey),
        'agentWrapperSuite': 1,
        'agentKeyFingerprint': fingerprintWire,
        'fieldIds': approvedFieldIds,
        'expiresAt': ?expiresAt,
        'remainingUses': ?remainingUses,
      };
    } finally {
      _wipe([grantKey, recipientKey, fingerprint, plaintext, wrappedKey]);
    }
  }

  int _methodBits(List<GrantMethod> methods) {
    var bits = 0;
    for (final method in methods) {
      bits |= switch (method) {
        GrantMethod.get => 1,
        GrantMethod.exec => 2,
        GrantMethod.inject => 4,
      };
    }
    if (bits == 0) throw const FormatException('Active grant has no methods');
    return bits;
  }

  String _incrementValue(String? raw, String name) {
    if (raw == null || !RegExp(r'^[1-9][0-9]*$').hasMatch(raw)) {
      throw FormatException('$name invalid');
    }
    final value = BigInt.parse(raw);
    if (value >= (BigInt.one << 64) - BigInt.one) {
      throw FormatException('$name overflow');
    }
    return (value + BigInt.one).toString();
  }

  int _incrementInt(int? raw, String name) {
    if (raw == null || raw < 1 || raw >= 0xffffffff) {
      throw FormatException('$name invalid');
    }
    return raw + 1;
  }

  String _canonicalInstant(DateTime value) {
    final wire = value.toUtc().toIso8601String();
    final withoutZeros = wire.replaceFirst(RegExp(r'0+Z$'), 'Z');
    return withoutZeros.replaceFirst('.Z', 'Z');
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

  AgentVisibilityPolicy _policyForUpdatedContent(
    EntryType type,
    Map<String, dynamic> content,
    AgentVisibilityPolicy policy,
  ) {
    if (type != EntryType.creditCard) return policy;
    final fields = Map<String, visibility.AgentFieldAccess>.from(policy.fields);
    final customFields = <String, visibility.AgentFieldAccess>{};
    final rawCustomFields = content['fields'];
    if (rawCustomFields is List) {
      for (final rawField in rawCustomFields.whereType<Map>()) {
        final id = rawField['id'];
        if (id is! String) continue;
        customFields[id] = switch (rawField['type']) {
          'totp' => visibility.AgentFieldAccess.onGrantDerived,
          'text' ||
          'multiline' ||
          'concealed' => visibility.AgentFieldAccess.onGrantRuntime,
          _ => visibility.AgentFieldAccess.never,
        };
      }
    }
    fields.removeWhere(
      (id, _) =>
          !const {
            'memberLabel',
            'agentLabel',
            'description',
            'icon',
            'color',
            'entryType',
            'notes',
            'cardholderName',
            'cardNumber',
            'expiryMonth',
            'expiryYear',
            'securityCode',
            'pin',
            'billingAddress',
          }.contains(id) &&
          !customFields.containsKey(id),
    );
    fields.addAll(customFields);
    for (final field in const ['pin', 'billingAddress']) {
      final value = content[field];
      fields[field] = value is String && value.isNotEmpty
          ? visibility.AgentFieldAccess.onGrantRuntime
          : visibility.AgentFieldAccess.never;
    }
    return policy.copyWith(fields: fields);
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
