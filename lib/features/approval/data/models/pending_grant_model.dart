import '../../../grants/domain/entities/grant_method.dart';
import '../../domain/entities/pending_grant.dart';

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
    this.reason,
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
  final String? reason;

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
      reason: json['reason'] as String?,
      methods: json['methods'] as String?,
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
      vaultName: vaultName,
      agentName: agentName,
      entryLabel: entryLabel,
      reason: reason,
      requestedMethods: parseGrantMethods(methods),
      isAgentRegistered: isAgentRegistered,
      createdAt: DateTime.parse(createdAt).toLocal(),
    );
  }
}
