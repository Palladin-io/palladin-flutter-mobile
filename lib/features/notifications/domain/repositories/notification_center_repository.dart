import '../entities/inbox_notification.dart';
import '../entities/notification_preference.dart';

abstract interface class NotificationCenterRepository {
  Future<NotificationPage> list({String? cursor});

  Future<NotificationSummary> summary();

  Future<void> markRead(String id);

  Future<void> markAllRead();

  Future<List<NotificationPreference>> preferences();

  Future<List<NotificationPreference>> updatePreference({
    required String type,
    bool? inboxEnabled,
    bool? signalREnabled,
    bool? pushEnabled,
  });
}
