import '../../domain/entities/audit_log_entry.dart';

/// Wire DTO for an audit log list item (`AuditLogListItem` on the backend).
///
/// Mirrors the canonical backend `AuditLogListItem` contract. Metadata is an
/// allow-listed structural dictionary produced by the Audit module; it must
/// never be logged by the client.
class AuditLogModel {
  const AuditLogModel({
    required this.id,
    required this.eventType,
    required this.actorType,
    required this.result,
    required this.occurredAt,
    required this.createdAt,
    this.userId,
    this.agentId,
    this.agentName,
    this.actorName,
    this.vaultId,
    this.entryId,
    this.metadata = const {},
  });

  final String id;
  final String eventType;
  final Object? actorType;
  final Object? result;
  final String occurredAt;
  final String createdAt;
  final String? userId;
  final String? agentId;
  final String? agentName;
  final String? actorName;
  final String? vaultId;
  final String? entryId;
  final Map<String, String> metadata;

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      id: json['id'] as String,
      eventType: json['eventType'] as String? ?? '',
      actorType: json['actorType'],
      result: json['result'],
      occurredAt: json['occurredAt'] as String,
      createdAt: json['createdAt'] as String,
      userId: json['userId'] as String?,
      agentId: json['agentId'] as String?,
      agentName: json['agentName'] as String?,
      actorName: json['actorName'] as String?,
      vaultId: json['vaultId'] as String?,
      entryId: json['entryId'] as String?,
      metadata: _metadata(json['metadata']),
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
      result: AuditResult.fromWire(result),
      occurredAt: DateTime.parse(occurredAt).toLocal(),
      createdAt: DateTime.parse(createdAt).toLocal(),
      userId: userId,
      agentId: agentId,
      agentName: agentName,
      actorName: actorName,
      vaultId: vaultId,
      entryId: entryId,
      metadata: metadata,
      localPresentationOnly: true,
    );
  }

  static Map<String, String> _metadata(Object? raw) {
    if (raw is! Map) return const {};
    return Map.unmodifiable({
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    });
  }
}
