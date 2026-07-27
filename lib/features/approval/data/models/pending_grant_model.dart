import '../../../grants/domain/entities/grant_method.dart';
import '../../domain/entities/pending_grant.dart';
import '../../domain/entities/encrypted_reason.dart';

/// DTO for a pending grant returned by `GET /api/dashboard/pending-grants`.
///
/// camelCase keys to match the .NET API. The `agentPublicKey` is the only
/// "key" field and is public by definition — it can only seal data *to*
/// the agent, never decrypt.
class PendingGrantModel {
  const PendingGrantModel({
    required this.grantId,
    required this.vaultId,
    required this.agentId,
    required this.entryId,
    required this.agentPublicKey,
    required this.createdAt,
    this.vaultName,
    this.agentName,
    this.entryLabel,
    required this.encryptedReason,
    this.recipientAgentKeyVersion,
    this.methods,
    this.isAgentRegistered = true,
  });

  final String grantId;
  final String vaultId;
  final String agentId;
  final String entryId;
  final String agentPublicKey;
  final String createdAt;
  final String? vaultName;
  final String? agentName;
  final String? entryLabel;
  final EncryptedReason encryptedReason;
  final int? recipientAgentKeyVersion;

  /// Combined-flags string the agent requested, e.g. "get, exec" (CVT-149).
  final String? methods;

  /// Whether the requesting agent is already enrolled. Defaults to `true`
  /// when the backend omits `agentRegistered`.
  final bool isAgentRegistered;

  factory PendingGrantModel.fromJson(Map<String, dynamic> json) {
    return PendingGrantModel(
      // Tolerate both `grantId` and `id` keys.
      grantId: (json['grantId'] ?? json['id']) as String,
      vaultId: json['vaultId'] as String,
      agentId: json['agentId'] as String,
      entryId: json['entryId'] as String,
      agentPublicKey: json['agentPublicKey'] as String,
      createdAt: json['createdAt'] as String,
      vaultName: json['vaultName'] as String?,
      agentName: json['agentName'] as String?,
      entryLabel: json['entryLabel'] as String?,
      encryptedReason: _encryptedReason(json),
      recipientAgentKeyVersion: json['recipientAgentKeyVersion'] as int?,
      methods: _methods(json['methods']),
      isAgentRegistered: json['agentRegistered'] as bool? ?? true,
    );
  }

  PendingGrant toEntity() {
    return PendingGrant(
      grantId: grantId,
      vaultId: vaultId,
      agentId: agentId,
      entryId: entryId,
      agentPublicKey: agentPublicKey,
      // The locked/push list remains structural. Canonical display metadata is
      // resolved only inside the explicit unlocked approval review.
      vaultName: null,
      agentName: null,
      entryLabel: null,
      encryptedReason: encryptedReason,
      recipientAgentKeyVersion: recipientAgentKeyVersion,
      requestedMethods: parseGrantMethods(methods),
      isAgentRegistered: isAgentRegistered,
      createdAt: DateTime.parse(createdAt).toLocal(),
    );
  }

  static String? _methods(Object? value) => switch (value) {
    String value => value,
    int value => [
      if ((value & 1) != 0) 'get',
      if ((value & 2) != 0) 'exec',
      if ((value & 4) != 0) 'inject',
    ].join(', '),
    _ => null,
  };

  static EncryptedReason _encryptedReason(Map<String, dynamic> grant) {
    final value = grant['encryptedReason'];
    if (value is! Map) throw const FormatException('Missing encrypted reason');
    final json = Map<String, dynamic>.from(value);
    String text(String key) => json[key] as String;
    int number(String key) => json[key] as int;
    final result = EncryptedReason(
      organizationId: text('organizationId'),
      vaultId: text('vaultId'),
      entryId: text('entryId'),
      grantRequestId: text('grantRequestId'),
      agentId: text('agentId'),
      requestRevision: text('requestRevision'),
      header: Map<String, dynamic>.from(json['header'] as Map),
      reasonKeyVersion: number('reasonKeyVersion'),
      agentMessageKeyVersion: number('agentMessageKeyVersion'),
      recipientAgentMessageKeyFingerprint: text(
        'recipientAgentMessageKeyFingerprint',
      ),
      requestedMethods: number('requestedMethods'),
      ciphertext: text('ciphertext'),
      agentMessageWrappedReasonDek: text('agentMessageWrappedReasonDek'),
      agentSignature: text('agentSignature'),
    );
    if (result.vaultId != grant['vaultId'] ||
        result.entryId != grant['entryId'] ||
        result.grantRequestId != (grant['grantId'] ?? grant['id']) ||
        result.agentId != grant['agentId'] ||
        result.header['protocolVersion'] != 2 ||
        result.header['algorithmSuite'] != 1 ||
        result.header['resourceKind'] != 3 ||
        result.header['projectionKind'] != 5 ||
        result.header['resourceRevision'] != result.requestRevision ||
        result.header['keyVersion'] != result.reasonKeyVersion ||
        result.requestedMethods != _methodMask(grant['methods'])) {
      throw const FormatException('Encrypted reason scope mismatch');
    }
    return result;
  }

  static int _methodMask(Object? value) {
    if (value is int) return value;
    var result = 0;
    for (final method in parseGrantMethods(value as String?)) {
      result |= switch (method) {
        GrantMethod.get => 1,
        GrantMethod.exec => 2,
        GrantMethod.inject => 4,
      };
    }
    return result;
  }
}
