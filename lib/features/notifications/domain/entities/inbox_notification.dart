/// A durable, user-visible item returned by `GET /api/notifications`.
///
/// Notification types and topics are intentionally open strings. Source
/// modules can add new values without requiring a mobile release.
class InboxNotification {
  const InboxNotification({
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

  bool get isOpenAction => isActionRequired && !isResolved;

  InboxNotification copyWith({
    bool? isRead,
    bool? isResolved,
    String? resolution,
  }) {
    return InboxNotification(
      id: id,
      type: type,
      topic: topic,
      title: title,
      body: body,
      data: data,
      isActionRequired: isActionRequired,
      isSecurityCritical: isSecurityCritical,
      isRead: isRead ?? this.isRead,
      isResolved: isResolved ?? this.isResolved,
      resolution: resolution ?? this.resolution,
      actionType: actionType,
      actionTarget: actionTarget,
      occurredAt: occurredAt,
    );
  }
}

class NotificationPage {
  const NotificationPage({required this.items, this.nextCursor});

  final List<InboxNotification> items;
  final String? nextCursor;
}

class NotificationSummary {
  const NotificationSummary({
    required this.unreadCount,
    required this.openActionRequiredCount,
  });

  final int unreadCount;
  final int openActionRequiredCount;
}
