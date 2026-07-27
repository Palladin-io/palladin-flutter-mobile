import '../../domain/entities/grant.dart';

/// DTO for a grant returned by the .NET backend.
///
/// camelCase keys to match the API. Carries metadata only — the grant
/// list/detail endpoints never return crypto material per the security
/// model, so there are no blob/nonce/wrapped-DEK fields here.
class GrantModel {
  const GrantModel({
    required this.id,
    required this.vaultId,
    required this.agentId,
    required this.status,
    required this.scope,
    required this.createdAt,
    this.agentName,
    this.agentIconKey,
    this.agentPublicKey,
    this.recipientAgentKeyVersion = 1,
    this.fieldIds = const [],
    this.vaultName,
    this.entryId,
    this.entryLabel,
    this.reason,
    this.methods,
    this.expiresAt,
    this.queryLimit,
    this.queryCount,
    this.approvedAt,
    this.approvedByName,
    this.revokedAt,
    this.createdByName,
    this.revokedByName,
    this.deniedByName,
    this.revokeReason,
    this.denyReason,
    this.canRevoke = false,
    this.canGrantAgain = false,
  });

  final String id;
  final String vaultId;
  final String agentId;
  final String? agentName;
  final String? agentIconKey;
  final String? agentPublicKey;
  final int recipientAgentKeyVersion;
  final List<String> fieldIds;
  final String? vaultName;
  final Object? status;
  final Object? scope;
  final String createdAt;
  final String? entryId;
  final String? entryLabel;
  final String? reason;
  final String? methods;
  final String? expiresAt;
  final int? queryLimit;
  final int? queryCount;
  final String? approvedAt;
  final String? approvedByName;
  final String? revokedAt;
  final String? createdByName;
  final String? revokedByName;
  final String? deniedByName;
  final String? revokeReason;
  final String? denyReason;
  final bool canRevoke;
  final bool canGrantAgain;

  factory GrantModel.fromJson(
    Map<String, dynamic> json, {
    String? contextVaultId,
  }) {
    return GrantModel(
      id: json['id'] as String,
      vaultId: contextVaultId ?? json['vaultId'] as String,
      agentId: json['agentId'] as String,
      agentName: json['agentName'] as String?,
      agentIconKey: json['agentIconKey'] as String?,
      agentPublicKey: json['agentPublicKey'] as String?,
      recipientAgentKeyVersion:
          (json['recipientAgentKeyVersion'] as num?)?.toInt() ?? 1,
      fieldIds:
          ((json['entryScopes'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .expand(
                (scope) => scope['fieldIds'] as List<dynamic>? ?? const [],
              )
              .whereType<String>()
              .toSet()
              .toList()
            ..sort()),
      vaultName: json['vaultName'] as String?,
      status: json['status'],
      // Org listing returns `type` (full/granular); the per-vault list uses
      // `mode`. Accept both so one model serves every grants endpoint.
      scope: json['type'] ?? json['mode'] ?? json['scope'] ?? json['grantMode'],
      createdAt: json['createdAt'] as String,
      entryId: json['entryId'] as String?,
      entryLabel: json['entryLabel'] as String?,
      reason: json['reason'] as String?,
      methods: json['methods'] as String?,
      expiresAt: json['expiresAt'] as String?,
      queryLimit: json['queryLimit'] as int?,
      queryCount: json['queryCount'] as int?,
      approvedAt: json['approvedAt'] as String?,
      approvedByName: json['approvedByName'] as String?,
      revokedAt: json['revokedAt'] as String?,
      createdByName: json['createdByName'] as String?,
      revokedByName: json['revokedByName'] as String?,
      deniedByName: json['deniedByName'] as String?,
      revokeReason: json['revokeReason'] as String?,
      denyReason: json['denyReason'] as String?,
      canRevoke: json['canRevoke'] as bool? ?? false,
      canGrantAgain: json['canGrantAgain'] as bool? ?? false,
    );
  }

  Grant toEntity() {
    DateTime? parse(String? raw) =>
        raw == null ? null : DateTime.parse(raw).toLocal();

    return Grant(
      id: id,
      vaultId: vaultId,
      agentId: agentId,
      agentName: agentName,
      agentIconKey: agentIconKey,
      agentPublicKey: agentPublicKey,
      recipientAgentKeyVersion: recipientAgentKeyVersion,
      fieldIds: fieldIds,
      vaultName: vaultName,
      status: GrantStatus.fromWire(status),
      scope: GrantScope.fromWire(scope),
      entryId: entryId,
      entryLabel: entryLabel,
      reason: reason,
      methods: parseGrantMethods(methods),
      createdAt: DateTime.parse(createdAt).toLocal(),
      expiresAt: parse(expiresAt),
      queryLimit: queryLimit,
      queryCount: queryCount,
      approvedAt: parse(approvedAt),
      approvedByName: approvedByName,
      revokedAt: parse(revokedAt),
      createdByName: createdByName,
      revokedByName: revokedByName,
      deniedByName: deniedByName,
      revokeReason: revokeReason,
      denyReason: denyReason,
      canRevoke: canRevoke,
      canGrantAgain: canGrantAgain,
    );
  }
}

/// One page of grants plus the cursor for the next page (cursor-based
/// pagination per the backend contract — `?cursor=&pageSize=`).
class GrantPage {
  const GrantPage({required this.grants, this.nextCursor});

  final List<GrantModel> grants;

  /// Opaque cursor for the next page, or `null` when this is the last
  /// page.
  final String? nextCursor;
}
