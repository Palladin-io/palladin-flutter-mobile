import '../entities/inbox_notification.dart';

abstract interface class NotificationCenterRepository {
  Future<NotificationPage> list({String? cursor});

  Future<NotificationSummary> summary();

  Future<void> markRead(String id);

  Future<void> markAllRead();
}
