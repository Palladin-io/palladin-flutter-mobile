import '../../domain/entities/inbox_notification.dart';

class InboxNotificationModel {
  const InboxNotificationModel({
    required this.id,
    required this.type,
    required this.topic,
    required this.title,
    required this.body,
    required this.data,
    required this.isActionRequired,
    required this.isSecurityCritical,
    required this.isRead,
    required this.isResolved,
    required this.occurredAt,
    this.resolution,
    this.actionType,
    this.actionTarget,
  });

  final String id;
  final String type;
  final String topic;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isActionRequired;
  final bool isSecurityCritical;
  final bool isRead;
  final bool isResolved;
  final String? resolution;
  final String? actionType;
  final String? actionTarget;
  final DateTime occurredAt;

  factory InboxNotificationModel.fromJson(Map<String, dynamic> json) {
    String string(String key) => json[key] as String? ?? '';
    String? nullableString(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final rawData = json['data'];
    return InboxNotificationModel(
      id: string('id'),
      type: string('type'),
      topic: string('topic'),
      title: string('title'),
      body: string('body'),
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : const <String, dynamic>{},
      isActionRequired: json['isActionRequired'] as bool? ?? false,
      isSecurityCritical: json['isSecurityCritical'] as bool? ?? false,
      isRead: json['isRead'] as bool? ?? false,
      isResolved: json['isResolved'] as bool? ?? false,
      resolution: nullableString('resolution'),
      actionType: nullableString('actionType'),
      actionTarget: nullableString('actionTarget'),
      occurredAt:
          DateTime.tryParse(string('occurredAt'))?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  InboxNotification toEntity() => InboxNotification(
    id: id,
    type: type,
    topic: topic,
    title: title,
    body: body,
    data: data,
    isActionRequired: isActionRequired,
    isSecurityCritical: isSecurityCritical,
    isRead: isRead,
    isResolved: isResolved,
    resolution: resolution,
    actionType: actionType,
    actionTarget: actionTarget,
    occurredAt: occurredAt,
  );
}
