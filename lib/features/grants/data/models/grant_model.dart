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
    this.entryId,
    this.entryLabel,
    this.reason,
    this.expiresAt,
    this.queryLimit,
    this.queryCount,
    this.approvedAt,
    this.approvedByName,
    this.revokedAt,
  });

  final String id;
  final String vaultId;
  final String agentId;
  final String? agentName;
  final Object? status;
  final Object? scope;
  final String createdAt;
  final String? entryId;
  final String? entryLabel;
  final String? reason;
  final String? expiresAt;
  final int? queryLimit;
  final int? queryCount;
  final String? approvedAt;
  final String? approvedByName;
  final String? revokedAt;

  factory GrantModel.fromJson(
    Map<String, dynamic> json, {
    String? contextVaultId,
  }) {
    return GrantModel(
      id: json['id'] as String,
      vaultId: contextVaultId ?? json['vaultId'] as String,
      agentId: json['agentId'] as String,
      agentName: json['agentName'] as String?,
      status: json['status'],
      scope: json['mode'] ?? json['scope'] ?? json['grantMode'],
      createdAt: json['createdAt'] as String,
      entryId: json['entryId'] as String?,
      entryLabel: json['entryLabel'] as String?,
      reason: json['reason'] as String?,
      expiresAt: json['expiresAt'] as String?,
      queryLimit: json['queryLimit'] as int?,
      queryCount: json['queryCount'] as int?,
      approvedAt: json['approvedAt'] as String?,
      approvedByName: json['approvedByName'] as String?,
      revokedAt: json['revokedAt'] as String?,
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
      status: GrantStatus.fromWire(status),
      scope: GrantScope.fromWire(scope),
      entryId: entryId,
      entryLabel: entryLabel,
      reason: reason,
      createdAt: DateTime.parse(createdAt).toLocal(),
      expiresAt: parse(expiresAt),
      queryLimit: queryLimit,
      queryCount: queryCount,
      approvedAt: parse(approvedAt),
      approvedByName: approvedByName,
      revokedAt: parse(revokedAt),
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
