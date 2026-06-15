import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/push_message.dart';

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
  PushNavigationCubit({required AnalyticsService analytics})
      : _analytics = analytics,
        super(null);

  final AnalyticsService _analytics;

  /// Handles a notification the user tapped. Fires the
  /// `mb:push:notification-tapped` analytics event and emits the
  /// resolved route (or `null` when there is nothing to navigate to).
  void onNotificationTapped(PushMessage message) {
    AppLogger.i('Push', 'Notification tapped: type=${message.type.name}');
    _analytics.capture('push', 'notification-tapped', properties: {
      'type': message.type.name,
    });

    final route = _resolveRoute(message);
    if (route == null) {
      AppLogger.d('Push', 'No deep-link target for type=${message.type.name}');
      return;
    }
    // Re-emit even if the route is identical to the current state so a
    // second tap on the same notification still navigates.
    emit(null);
    emit(route);
  }

  /// Clears the pending navigation target after the listener consumes it.
  void consumed() => emit(null);

  /// Maps a [PushMessage] to a router location.
  ///
  /// | type             | destination                               |
  /// |------------------|-------------------------------------------|
  /// | grant_pending    | `/inbox?focus=<id>` (owner business inbox)|
  /// | grant_revoked    | `/inbox?focus=<id>`                        |
  /// | credential_stale | `/inbox?focus=<id>`                        |
  /// | agent_pending    | `/agents/{agentId}` else `/agents`        |
  /// | grant_approved   | `/agents/{agentId}` else `/agents`        |
  /// | unknown          | `null` (no navigation)                    |
  String? _resolveRoute(PushMessage message) {
    switch (message.type) {
      // Inbox-owned notifications open the business Inbox, not agent detail.
      // Carry the notification id so the inbox can focus + mark it read.
      case PushNotificationType.grantPending:
      case PushNotificationType.grantRevoked:
      case PushNotificationType.credentialStale:
        final id = message.notificationId;
        return id != null ? '/inbox?focus=$id' : '/inbox';
      case PushNotificationType.grantApproved:
      case PushNotificationType.agentPending:
        final agentId = message.agentId;
        return agentId != null ? '/agents/$agentId' : '/agents';
      case PushNotificationType.unknown:
        return null;
    }
  }
}
