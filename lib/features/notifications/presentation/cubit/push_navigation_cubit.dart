import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/push_message.dart';
import '../../domain/repositories/notification_center_repository.dart';

/// Drives deep-link navigation in response to a tapped push notification.
///
/// The [PushNotificationService] forwards every *tapped* message (from
/// the background, terminated, or cold-start paths) here. This cubit
/// resolves it to a target route string and emits it; a [BlocListener]
/// in `app.dart` performs the actual `router.go(...)`. Keeping the
/// route resolution here means the navigation table is unit-testable and
/// the widget layer stays dumb.
///
/// Emits `null` for messages that have no meaningful destination (e.g.
/// [PushNotificationType.unknown]) so the listener can no-op.
class PushNavigationCubit extends Cubit<String?> {
  PushNavigationCubit({
    required AnalyticsService analytics,
    required NotificationCenterRepository repository,
  }) : _analytics = analytics,
       _repository = repository,
       super(null);

  final AnalyticsService _analytics;
  final NotificationCenterRepository _repository;
  bool _resolving = false;

  /// Handles a notification the user tapped. Fires the
  /// `mb:push:notification-tapped` analytics event and emits the
  /// resolved route (or `null` when there is nothing to navigate to).
  Future<void> onNotificationTapped(PushMessage message) async {
    if (_resolving) return;
    _resolving = true;
    AppLogger.i('Push', 'Notification tapped');
    _analytics.capture(
      'push',
      'notification-tapped',
      properties: {'type': message.type.name},
    );

    try {
      final id = await _resolveAuthorizedInboxId(message);
      if (id == null) return;
      emit(null);
      emit('/inbox?focus=${Uri.encodeQueryComponent(id)}');
    } catch (_) {
      // 401/403/404, deleted references and network failures fail closed.
      AppLogger.w('Push', 'Inbox notification could not be resolved');
    } finally {
      _resolving = false;
    }
  }

  /// Clears the pending navigation target after the listener consumes it.
  void consumed() => emit(null);

  /// Resolves one structural event against at most 500 current Inbox rows.
  /// Pages are inspected and discarded one at a time; the feed is not
  /// accumulated in memory.
  Future<String?> _resolveAuthorizedInboxId(PushMessage message) async {
    String? cursor;
    var inspected = 0;
    do {
      final page = await _repository.list(cursor: cursor);
      for (final item in page.items) {
        inspected++;
        if (item.subjectId == message.subjectId &&
            item.type == message.type.wireValue &&
            item.category.name == message.category &&
            item.occurredAt.toUtc() == message.occurredAt.toUtc()) {
          return item.id;
        }
        if (inspected >= 500) return null;
      }
      final next = page.nextCursor;
      if (next == null || next == cursor) return null;
      cursor = next;
    } while (true);
  }
}
