import '../../domain/entities/audit_log_entry.dart';

/// Wire DTO for an audit log list item (`AuditLogListItem` on the backend).
///
/// Only structural fields cross this boundary. Server-provided presentation
/// text is deliberately discarded and resolved from scoped local directories.
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
    return AuditLogModel(
      id: json['id'] as String,
      eventType: json['eventType'] as String? ?? '',
      actorType: json['actorType'],
      createdAt: json['createdAt'] as String,
      userId: json['userId'] as String?,
      agentId: json['agentId'] as String?,
      agentName: null,
      actorName: null,
      vaultId: json['vaultId'] as String?,
      entryId: json['entryId'] as String?,
      entryLabel: null,
      agentReason: null,
      metadata: const {},
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
      vaultId: vaultId,
      entryId: entryId,
      localPresentationOnly: true,
    );
  }
}
