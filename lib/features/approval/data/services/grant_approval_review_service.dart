import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/utils/app_logger.dart';

import '../../../vault/data/datasources/agent_discovery_remote_datasource.dart';
import '../../../vault/data/datasources/vault_remote_datasource.dart';
import '../../../vault/data/services/agent_visibility_projector.dart';
import '../../../vault/data/services/canonical_entry_detail_service.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import '../../../vault/data/services/vault_rotation_crypto_service.dart';
import '../../../vault/domain/entities/agent_visibility_policy.dart';
import '../../../vault/domain/entities/entry_entity.dart';
import '../datasources/approval_remote_datasource.dart';
import '../../domain/entities/pending_grant.dart';
import 'encrypted_reason_crypto_service.dart';
import 'pending_grant_reason_binding.dart';

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
    EncryptedReasonCryptoService? reasonCrypto,
  }) : _vaults = vaults,
       _entries = entries,
       _keys = keys,
       _discovery = discovery,
       _approval = approval,
       _reasonCrypto = reasonCrypto ?? EncryptedReasonCryptoService();

  final VaultRemoteDatasource _vaults;
  final CanonicalEntryDetailService _entries;
  final VaultRotationCryptoService _keys;
  final AgentDiscoveryRemote _discovery;
  final ApprovalRemoteDatasource _approval;
  final EncryptedReasonCryptoService _reasonCrypto;

  @override
  Future<GrantApprovalReview> open({
    required PendingGrant grant,
    required Uint8List memberPrivateKey,
  }) async {
    var stage = 'grant-fetch';
    Uint8List? vaultKey;
    Uint8List? messagePrivateKey;
    Uint8List? messagePublicKey;
    Uint8List? signingKey;
    Uint8List? reasonKey;
    Uint8List? plaintext;
    CanonicalEntrySnapshot? entry;
    try {
      final freshModel = await _approval.getGrant(grant.vaultId, grant.grantId);
      stage = 'grant-parse';
      final fresh = freshModel.toEntity();
      stage = 'scope-validation';
      final reason = requireBoundGrantReason(fresh);
      stage = 'vault-fetch';
      final vault = await _vaults.getEncryptedVault(grant.vaultId);
      stage = 'vault-validation';
      _validateVaultContext(fresh, vault);
      stage = 'agent-discovery';
      final candidates = (await _discovery.list(grant.vaultId))
          .where((item) => item.agentId == fresh.agentId && item.isCurrent)
          .toList(growable: false);
      if (candidates.length != 1) {
        throw const FormatException('Agent identity is not current');
      }
      final candidate = candidates.single;
      stage = 'signing-key';
      signingKey = VaultProtocolBytes.base64Decode(
        candidate.ed25519PublicKey,
        maximumBytes: 32,
      );
      stage = 'vault-key';
      vaultKey = await _keys.openMemberVaultKey(
        Map<String, dynamic>.from(vault['memberVaultKey'] as Map),
        memberPrivateKey,
      );
      stage = 'message-key-selection';
      final messageKeyEnvelope =
          VaultRotationCryptoService.requirePrivateKeyEnvelope(
            envelopes: vault['vaultPrivateKeys'],
            purpose: 'vaultAgentMessagePrivateKey',
            keyVersion: reason.agentMessageKeyVersion,
          );
      stage = 'message-key';
      final openedMessagePrivateKey = await _keys
          .openCanonicalAgentMessagePrivateKey(
            messageKeyEnvelope,
            vaultKey,
            expectedKeyVersion: reason.agentMessageKeyVersion,
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
      stage = 'reason-key';
      reasonKey = await _reasonCrypto.verifyAndOpenKey(
        reason: reason,
        signingPublicKey: signingKey,
        recipientPrivateKey: openedMessagePrivateKey,
      );
      final openedReasonKey = reasonKey;
      if (openedReasonKey.length != 32) {
        throw const FormatException('Invalid ReasonDEK');
      }
      stage = 'reason-decrypt';
      plaintext = await _reasonCrypto.decrypt(
        reason: reason,
        reasonKey: openedReasonKey,
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
      stage = 'entry-reveal';
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
      final agentLabel =
          entry.secret['agentLabel'] as String? ??
          entry.secret['memberLabel'] as String;
      final description = entry.secret['description'] as String? ?? '';
      final grantableFieldIds = AgentVisibilityProjector.grantableFieldIds(
        type: type,
        agentLabel: agentLabel,
        description: description,
        content: entry.payload,
        policy: policy,
      );
      final fields = grantableFieldIds
          .map(
            (id) => GrantableApprovalField(
              id: id,
              label: _fieldLabel(id, entry!.payload),
              access: policy.fields[id]!,
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
    } catch (error) {
      // Stage and exception class are safe operational metadata. Never log
      // exception messages here: crypto/parser errors may carry input data.
      AppLogger.w('Approval', 'Review failed at $stage (${error.runtimeType})');
      rethrow;
    } finally {
      entry?.clear();
      for (final value in [
        vaultKey,
        messagePrivateKey,
        messagePublicKey,
        signingKey,
        reasonKey,
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

  void _validateVaultContext(PendingGrant grant, Map<String, dynamic> vault) {
    final reason = grant.encryptedReason;
    if (reason == null ||
        reason.organizationId != vault['organizationId'] ||
        reason.memberKeyGeneration != vault['memberKeyGeneration']) {
      throw const FormatException('Encrypted reason Vault context mismatch');
    }
  }
}
