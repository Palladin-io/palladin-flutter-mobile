import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';

import '../../../vault/data/datasources/agent_discovery_remote_datasource.dart';
import '../../../vault/data/datasources/vault_remote_datasource.dart';
import '../../../vault/data/services/canonical_entry_detail_service.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_aad.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import '../../../vault/data/services/vault_rotation_crypto_service.dart';
import '../../../vault/domain/entities/agent_visibility_policy.dart';
import '../../../vault/domain/entities/entry_entity.dart';
import '../datasources/approval_remote_datasource.dart';
import '../../domain/entities/pending_grant.dart';

final class GrantableApprovalField {
  const GrantableApprovalField({
    required this.id,
    required this.label,
    required this.access,
  });
  final String id;
  final String label;
  final AgentFieldAccess access;
}

/// Decrypted approval material. It must remain factory-scoped and be cleared
/// on lock, background, conflict, error and disposal.
final class GrantApprovalReview {
  GrantApprovalReview({
    required this.reason,
    required this.entryLabel,
    required this.entryRevision,
    required this.agentName,
    required this.fields,
  });

  String reason;
  String entryLabel;
  final String entryRevision;
  final String? agentName;
  final List<GrantableApprovalField> fields;

  void clear() {
    reason = '';
    entryLabel = '';
    fields.clear();
  }
}

/// Authenticates and opens the encrypted reason and canonical Entry locally.
abstract interface class GrantApprovalReviewer {
  Future<GrantApprovalReview> open({
    required PendingGrant grant,
    required Uint8List memberPrivateKey,
  });
}

/// Network and crypto implementation of [GrantApprovalReviewer].
final class GrantApprovalReviewService implements GrantApprovalReviewer {
  GrantApprovalReviewService({
    required VaultRemoteDatasource vaults,
    required CanonicalEntryDetailService entries,
    required VaultRotationCryptoService keys,
    required VaultProtocolEnvelopeService envelopes,
    required VaultProtocolSignatureService signatures,
    required AgentDiscoveryRemote discovery,
    required ApprovalRemoteDatasource approval,
  }) : _vaults = vaults,
       _entries = entries,
       _keys = keys,
       _envelopes = envelopes,
       _signatures = signatures,
       _discovery = discovery,
       _approval = approval;

  final VaultRemoteDatasource _vaults;
  final CanonicalEntryDetailService _entries;
  final VaultRotationCryptoService _keys;
  final VaultProtocolEnvelopeService _envelopes;
  final VaultProtocolSignatureService _signatures;
  final AgentDiscoveryRemote _discovery;
  final ApprovalRemoteDatasource _approval;

  @override
  Future<GrantApprovalReview> open({
    required PendingGrant grant,
    required Uint8List memberPrivateKey,
  }) async {
    final fresh = (await _approval.getGrant(
      grant.vaultId,
      grant.grantId,
    )).toEntity();
    final reason = fresh.encryptedReason;
    Uint8List? vaultKey;
    Uint8List? messagePrivateKey;
    Uint8List? messagePublicKey;
    Uint8List? reasonKey;
    Uint8List? wrappedReasonKey;
    Uint8List? plaintext;
    CanonicalEntrySnapshot? entry;
    try {
      _validateScope(fresh);
      final vault = await _vaults.getEncryptedVault(grant.vaultId);
      _validateVaultContext(fresh, vault);
      final candidates = (await _discovery.list(grant.vaultId))
          .where((item) => item.agentId == fresh.agentId && item.isCurrent)
          .toList(growable: false);
      if (candidates.length != 1) {
        throw const FormatException('Agent identity is not current');
      }
      final candidate = candidates.single;
      final signingKey = VaultProtocolBytes.base64UrlDecode(
        candidate.ed25519PublicKey,
        maximumBytes: 32,
      );
      try {
        if (!await _signatures.verify(
          domainPrefix: 'PLDNV2SIG:ENCRYPTED-REASON:',
          unsignedObject: _unsignedReason(reason),
          signature: reason.agentSignature,
          publicKey: signingKey,
        )) {
          throw const FormatException('Encrypted reason signature mismatch');
        }
      } finally {
        signingKey.fillRange(0, signingKey.length, 0);
      }
      vaultKey = await _keys.openMemberVaultKey(
        Map<String, dynamic>.from(vault['memberVaultKey'] as Map),
        memberPrivateKey,
      );
      final privateKeys = (vault['vaultPrivateKeys'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .where(
            (item) =>
                item['privateKeyKind'] == 1 &&
                item['privateKeyVersion'] == reason.agentMessageKeyVersion,
          )
          .toList(growable: false);
      if (privateKeys.length != 1) {
        throw const FormatException('Message key is unavailable');
      }
      final openedMessagePrivateKey = await _keys.openPrivateKey(
        privateKeys.single,
        vaultKey,
      );
      messagePrivateKey = openedMessagePrivateKey;
      final sodium = await SodiumProvider.instance();
      final secret = SecureKey.fromList(sodium, openedMessagePrivateKey);
      final Uint8List openedMessagePublicKey;
      try {
        openedMessagePublicKey = sodium.crypto.scalarmult.base(n: secret);
        messagePublicKey = openedMessagePublicKey;
      } finally {
        secret.dispose();
      }
      final fingerprint = VaultProtocolBytes.base64UrlEncode(
        vaultPublicKeyFingerprint(
          VaultPublicKeyKind.vaultMessageX25519,
          openedMessagePublicKey,
        ),
      );
      if (fingerprint != reason.recipientAgentMessageKeyFingerprint) {
        throw const FormatException('Encrypted reason recipient mismatch');
      }
      wrappedReasonKey = VaultProtocolBytes.base64UrlDecode(
        reason.agentMessageWrappedReasonDek,
        maximumBytes: 128,
      );
      reasonKey = await _envelopes.openPackage(
        ciphertext: wrappedReasonKey,
        recipientPublicKey: openedMessagePublicKey,
        recipientPrivateKey: openedMessagePrivateKey,
      );
      final openedReasonKey = reasonKey;
      if (openedReasonKey.length != 32) {
        throw const FormatException('Invalid ReasonDEK');
      }
      final envelope = _reasonEnvelope(reason);
      plaintext = await _envelopes.decrypt(
        profile: VaultAadProfile.encryptedReason,
        envelope: envelope,
        key: openedReasonKey,
        expected: VaultEnvelopeExpectations(
          aadContext: envelope,
          minimumMemberKeyGeneration:
              reason.header['memberKeyGeneration'] as int,
        ),
      );
      final decoded = jsonDecode(utf8.decode(plaintext, allowMalformed: false));
      if (decoded is! Map ||
          decoded.length != 1 ||
          decoded['reason'] is! String) {
        throw const FormatException('Malformed encrypted reason');
      }
      final reasonText = (decoded['reason'] as String).trim();
      if (reasonText.isEmpty || utf8.encode(reasonText).length > 4096) {
        throw const FormatException('Invalid encrypted reason');
      }
      entry = await _entries.reveal(
        expected: EntryEntity(
          id: grant.entryId,
          vaultId: grant.vaultId,
          label: '',
          type: EntryType.key,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        memberPrivateKey: memberPrivateKey,
      );
      final type = EntryTypeExtension.fromWire(
        entry.secret['entryType'] as int,
      );
      final policy = AgentVisibilityPolicy.fromJson(
        type,
        Map<String, dynamic>.from(entry.secret['agentVisibilityPolicy'] as Map),
        content: entry.payload,
      );
      final fields = policy.fields.entries
          .where(
            (item) =>
                item.value != AgentFieldAccess.never &&
                item.value != AgentFieldAccess.discovery,
          )
          .map(
            (item) => GrantableApprovalField(
              id: item.key,
              label: _fieldLabel(item.key, entry!.payload),
              access: item.value,
            ),
          )
          .toList(growable: true);
      if (fields.isEmpty) throw const FormatException('No grantable fields');
      return GrantApprovalReview(
        reason: reasonText,
        entryLabel: entry.secret['memberLabel'] as String,
        entryRevision: entry.entry['currentRevision'] as String,
        agentName: candidate.agentName,
        fields: fields,
      );
    } finally {
      entry?.clear();
      for (final value in [
        vaultKey,
        messagePrivateKey,
        messagePublicKey,
        reasonKey,
        wrappedReasonKey,
        plaintext,
      ]) {
        value?.fillRange(0, value.length, 0);
      }
    }
  }

  String _fieldLabel(String id, Map<String, dynamic> content) {
    final custom = content['fields'];
    if (custom is List) {
      for (final item in custom.whereType<Map>()) {
        if (item['id'] == id && item['label'] is String) {
          return item['label'] as String;
        }
      }
    }
    return id;
  }

  void _validateScope(PendingGrant grant) {
    final reason = grant.encryptedReason;
    if (reason.vaultId != grant.vaultId ||
        reason.entryId != grant.entryId ||
        reason.grantRequestId != grant.grantId ||
        reason.agentId != grant.agentId ||
        reason.header['resourceRevision'] != reason.requestRevision ||
        reason.header['keyVersion'] != reason.reasonKeyVersion ||
        reason.header['protocolVersion'] != 2 ||
        reason.header['algorithmSuite'] != 1 ||
        reason.header['resourceKind'] != 3 ||
        reason.header['projectionKind'] != 5 ||
        reason.requestedMethods != _methodBits(grant.requestedMethods)) {
      throw const FormatException('Encrypted reason scope mismatch');
    }
  }

  void _validateVaultContext(PendingGrant grant, Map<String, dynamic> vault) {
    final reason = grant.encryptedReason;
    if (reason.organizationId != vault['organizationId'] ||
        reason.header['memberKeyGeneration'] != vault['memberKeyGeneration']) {
      throw const FormatException('Encrypted reason Vault context mismatch');
    }
  }

  int _methodBits(Iterable<dynamic> methods) {
    var bits = 0;
    for (final method in methods) {
      bits |= switch (method.name) {
        'get' => 1,
        'exec' => 2,
        'inject' => 4,
        _ => 0,
      };
    }
    return bits;
  }

  Map<String, Object?> _unsignedReason(dynamic reason) => {
    'agentId': reason.agentId,
    'agentMessageKeyVersion': reason.agentMessageKeyVersion,
    'agentMessageWrappedReasonDek': reason.agentMessageWrappedReasonDek,
    'ciphertext': reason.ciphertext,
    'entryId': reason.entryId,
    'grantRequestId': reason.grantRequestId,
    'header': reason.header,
    'organizationId': reason.organizationId,
    'reasonKeyVersion': reason.reasonKeyVersion,
    'recipientAgentMessageKeyFingerprint':
        reason.recipientAgentMessageKeyFingerprint,
    'requestRevision': reason.requestRevision,
    'requestedMethods': reason.requestedMethods,
    'vaultId': reason.vaultId,
  };

  Map<String, dynamic> _reasonEnvelope(dynamic reason) => {
    ..._unsignedReason(reason),
    'header': Map<String, dynamic>.from(reason.header as Map),
    'ciphertext': reason.ciphertext,
  };
}
