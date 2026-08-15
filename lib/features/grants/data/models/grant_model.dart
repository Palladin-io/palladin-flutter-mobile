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
    this.agentId,
    required this.status,
    required this.scope,
    required this.createdAt,
    this.agentName,
    this.agentIconKey,
    this.agentPublicKey,
    this.recipientAgentKeyVersion,
    this.entryScopes = const [],
    this.vaultName,
    this.entryId,
    this.entryLabel,
    this.reason,
    this.encryptedReason,
    this.methods,
    this.expiresAt,
    this.queryLimit,
    this.queryCount,
    this.approvedAt,
    this.approvedByName,
    this.revokedAt,
    this.createdBy,
    this.createdByName,
    this.revokedBy,
    this.revokedByName,
    this.deniedBy,
    this.deniedByName,
    this.denyReason,
    this.canRevoke = false,
    this.canGrantAgain = false,
  });

  final String id;
  final String vaultId;
  final String? agentId;
  final String? agentName;
  final String? agentIconKey;
  final String? agentPublicKey;
  final int? recipientAgentKeyVersion;
  final List<GrantEntryScope> entryScopes;
  final String? vaultName;
  final Object? status;
  final Object? scope;
  final String createdAt;
  final String? entryId;
  final String? entryLabel;
  final String? reason;
  final Map<String, dynamic>? encryptedReason;
  final String? methods;
  final String? expiresAt;
  final int? queryLimit;
  final int? queryCount;
  final String? approvedAt;
  final String? approvedByName;
  final String? revokedAt;
  final String? createdBy;
  final String? createdByName;
  final String? revokedBy;
  final String? revokedByName;
  final String? deniedBy;
  final String? deniedByName;
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
      agentId: json['agentId'] as String?,
      agentName: json['agentName'] as String?,
      agentIconKey: json['agentIconKey'] as String?,
      agentPublicKey: json['agentPublicKey'] as String?,
      recipientAgentKeyVersion: json['recipientAgentKeyVersion'] as int?,
      entryScopes: (json['entryScopes'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (scope) => GrantEntryScope(
              entryId: scope['entryId'] as String,
              fieldIds: (scope['fieldIds'] as List<dynamic>? ?? const [])
                  .whereType<String>()
                  .toList(growable: false),
              grantEnvelopeRevision: scope['grantEnvelopeRevision'] as String?,
              entryRevision: scope['entryRevision'] as String?,
              grantKeyVersion: scope['grantKeyVersion'] as int?,
              memberKeyGeneration: scope['memberKeyGeneration'] as int?,
              recipientAgentKeyVersion:
                  scope['recipientAgentKeyVersion'] as int?,
              agentKeyFingerprint: scope['agentKeyFingerprint'] as String?,
            ),
          )
          .toList(growable: false),
      vaultName: json['vaultName'] as String?,
      status: json['status'],
      // Org listing returns `type` (full/granular); the per-vault list uses
      // `mode`. Accept both so one model serves every grants endpoint.
      scope: json['type'] ?? json['mode'] ?? json['scope'] ?? json['grantMode'],
      createdAt: json['createdAt'] as String,
      entryId: json['entryId'] as String?,
      entryLabel: json['entryLabel'] as String?,
      reason: json['reason'] as String?,
      encryptedReason: _encryptedReason(json['encryptedReason']),
      methods: json['methods'] as String?,
      expiresAt: json['expiresAt'] as String?,
      queryLimit: json['queryLimit'] as int?,
      queryCount: json['queryCount'] as int?,
      approvedAt: json['approvedAt'] as String?,
      approvedByName: json['approvedByName'] as String?,
      revokedAt: json['revokedAt'] as String?,
      createdBy: json['createdBy'] as String?,
      createdByName: json['createdByName'] as String?,
      revokedBy: json['revokedBy'] as String?,
      revokedByName: json['revokedByName'] as String?,
      deniedBy: json['deniedBy'] as String?,
      deniedByName: json['deniedByName'] as String?,
      denyReason: json['denyReason'] as String?,
      canRevoke: json['canRevoke'] as bool? ?? false,
      canGrantAgain: json['canGrantAgain'] as bool? ?? false,
    );
  }

  Grant toEntity({String? resolvedReason}) {
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
      entryScopes: entryScopes,
      vaultName: vaultName,
      status: GrantStatus.fromWire(status),
      scope: GrantScope.fromWire(scope),
      entryId: entryId,
      entryLabel: entryLabel,
      reason: resolvedReason ?? reason,
      methods: parseGrantMethods(methods),
      createdAt: DateTime.parse(createdAt).toLocal(),
      expiresAt: parse(expiresAt),
      queryLimit: queryLimit,
      queryCount: queryCount,
      approvedAt: parse(approvedAt),
      approvedByName: approvedByName,
      revokedAt: parse(revokedAt),
      createdBy: createdBy,
      createdByName: createdByName,
      revokedBy: revokedBy,
      revokedByName: revokedByName,
      deniedBy: deniedBy,
      deniedByName: deniedByName,
      denyReason: denyReason,
      canRevoke: canRevoke,
      canGrantAgain: canGrantAgain,
    );
  }

  static Map<String, dynamic>? _encryptedReason(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;
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
