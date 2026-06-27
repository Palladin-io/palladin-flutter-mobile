import '../../domain/entities/audit_log_entry.dart';

/// Wire DTO for an audit log list item (`AuditLogListItem` on the backend).
///
/// Carries non-sensitive context only — ids, the entry label, the agent's
/// stated reason and a flat metadata map. Never any crypto material.
class AuditLogModel {
  const AuditLogModel({
    required this.id,
    required this.eventType,
    required this.actorType,
    required this.createdAt,
    this.userId,
    this.agentId,
    this.agentName,
    this.actorName,
    this.vaultId,
    this.entryId,
    this.entryLabel,
    this.agentReason,
    this.metadata = const {},
  });

  final String id;
  final String eventType;
  final Object? actorType;
  final String createdAt;
  final String? userId;
  final String? agentId;
  final String? agentName;
  final String? actorName;
  final String? vaultId;
  final String? entryId;
  final String? entryLabel;
  final String? agentReason;
  final Map<String, String> metadata;

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    final rawMeta = json['metadata'] as Map<String, dynamic>? ?? const {};
    return AuditLogModel(
      id: json['id'] as String,
      eventType: json['eventType'] as String? ?? '',
      actorType: json['actorType'],
      createdAt: json['createdAt'] as String,
      userId: json['userId'] as String?,
      agentId: json['agentId'] as String?,
      agentName: json['agentName'] as String?,
      actorName: json['actorName'] as String?,
      vaultId: json['vaultId'] as String?,
      entryId: json['entryId'] as String?,
      entryLabel: json['entryLabel'] as String?,
      agentReason: json['agentReason'] as String?,
      metadata: rawMeta.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );
  }

  /// Maps the DTO to a domain entity. Timestamps are converted to local
  /// time; unknown event types degrade gracefully to
  /// [AuditEventType.unknown] while preserving the raw string.
  AuditLogEntry toEntity() {
    return AuditLogEntry(
      id: id,
      eventType: AuditEventType.fromWire(eventType),
      rawEventType: eventType,
      actorType: AuditActorType.fromWire(actorType),
      createdAt: DateTime.parse(createdAt).toLocal(),
      userId: userId,
      agentId: agentId,
      agentName: agentName,
      actorName: actorName,
      vaultId: vaultId,
      entryId: entryId,
      entryLabel: entryLabel,
      agentReason: agentReason,
      metadata: metadata,
    );
  }
}
