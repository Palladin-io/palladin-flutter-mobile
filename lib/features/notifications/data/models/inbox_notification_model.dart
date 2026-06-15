import '../../domain/entities/inbox_notification.dart';

/// JSON ⇄ entity mapper for a `NotificationItem` from the frozen contract:
/// `{ id, type, category, titleKey, metadata, occurredAt, readAt?, actionState }`.
class InboxNotificationModel {
  const InboxNotificationModel({
    required this.id,
    required this.type,
    required this.category,
    required this.titleKey,
    required this.metadata,
    required this.actionState,
    required this.occurredAt,
    this.readAt,
  });

  final String id;
  final String type;
  final String category;
  final String titleKey;
  final Map<String, dynamic> metadata;
  final String? actionState;
  final String occurredAt;
  final String? readAt;

  factory InboxNotificationModel.fromJson(Map<String, dynamic> json) {
    String string(String key) => json[key] as String? ?? '';
    String? nullableString(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final rawMetadata = json['metadata'];
    return InboxNotificationModel(
      id: string('id'),
      type: string('type'),
      category: string('category'),
      titleKey: string('titleKey'),
      metadata: rawMetadata is Map
          ? Map<String, dynamic>.from(rawMetadata)
          : const <String, dynamic>{},
      actionState: nullableString('actionState'),
      occurredAt: string('occurredAt'),
      readAt: nullableString('readAt'),
    );
  }

  InboxNotification toEntity() => InboxNotification(
    id: id,
    type: type,
    category: NotificationCategory.fromWire(category),
    titleKey: titleKey,
    metadata: metadata,
    actionState: NotificationActionState.fromWire(actionState),
    occurredAt:
        DateTime.tryParse(occurredAt)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    readAt: readAt == null ? null : DateTime.tryParse(readAt!)?.toLocal(),
  );
}
