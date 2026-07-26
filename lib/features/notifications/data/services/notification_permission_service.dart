import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../../core/utils/app_logger.dart';

/// OS-level push notification permission status.
enum NotificationPermissionStatus {
  /// Permission is granted (iOS: authorized or provisional on the first
  /// request; Android: implicitly granted below API 33, explicitly on 33+).
  authorized,

  /// The user explicitly denied the permission request.
  ///
  /// On iOS the OS will no longer show the native prompt — use
  /// [NotificationPermissionService.openSettings] to send them to Settings.
  denied,

  /// Permission has not been requested yet.
  notDetermined,
}

/// Thin wrapper around [FirebaseMessaging] for notification permission
/// operations and a system-settings deep-link helper.
///
/// Registered as a DI singleton so it can be injected into cubits without
/// pulling [FirebaseMessaging] directly into presentation-layer tests.
class NotificationPermissionService {
  NotificationPermissionService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  /// Returns the current OS permission status without prompting the user.
  ///
  /// Catches all errors and returns [NotificationPermissionStatus.notDetermined]
  /// as a safe fallback so callers never need to guard the call.
  Future<NotificationPermissionStatus> checkStatus() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      return _toStatus(settings.authorizationStatus);
    } catch (_) {
      AppLogger.e(
        'NotificationPermission',
        'checkStatus failed — treating as notDetermined',
      );
      return NotificationPermissionStatus.notDetermined;
    }
  }

  /// Shows the OS native permission prompt if not yet decided.
  ///
  /// On iOS, once the user has denied, the OS will NOT re-show the prompt
  /// and this returns [NotificationPermissionStatus.denied] immediately.
  /// In that case, call [openSettings] to send the user to system Settings.
  ///
  /// Catches all errors and returns [NotificationPermissionStatus.notDetermined]
  /// so callers never need to guard the call.
  Future<NotificationPermissionStatus> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission();
      return _toStatus(settings.authorizationStatus);
    } catch (_) {
      AppLogger.e(
        'NotificationPermission',
        'requestPermission failed — treating as notDetermined',
      );
      return NotificationPermissionStatus.notDetermined;
    }
  }

  /// Opens the Notification settings for this app in the OS Settings.
  ///
  /// On Android and iOS 16+, deep-links directly to the per-app notification
  /// settings panel. On older iOS it falls back to the general app settings
  /// page where the user can tap through to Notifications.
  ///
  /// Use when [requestPermission] returns [NotificationPermissionStatus.denied]
  /// and the OS will no longer show the native prompt.
  Future<void> openSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (_) {
      AppLogger.e('NotificationPermission', 'openSettings failed');
    }
  }

  NotificationPermissionStatus _toStatus(AuthorizationStatus status) {
    return switch (status) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional =>
        NotificationPermissionStatus.authorized,
      AuthorizationStatus.denied => NotificationPermissionStatus.denied,
      _ => NotificationPermissionStatus.notDetermined,
    };
  }
}
