import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/push_message.dart';
import '../datasources/push_token_remote_datasource.dart';

/// Android notification channel used for foreground heads-up banners.
///
/// Must match the `default_notification_channel_id` meta-data declared in
/// AndroidManifest.xml so background notifications land in the same
/// channel.
const _androidChannel = AndroidNotificationChannel(
  'clawvault_default',
  'Claw Vault',
  description: 'Grant approvals and agent activity',
  importance: Importance.high,
);

/// Top-level FCM background handler.
///
/// Must be a top-level (or static) function — Firebase spins up a
/// separate isolate for background messages, so it cannot be a closure or
/// instance method. We intentionally do **no** work here beyond a
/// debug-safe log: the OS already renders the `notification` block, and
/// tap-routing is handled by [FirebaseMessaging.onMessageOpenedApp] /
/// [FirebaseMessaging.instance.getInitialMessage] when the app resumes.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No secret material is ever logged — only the routing type.
  AppLogger.d('Push', 'Background message: type=${message.data['type']}');
}

/// Owns the device's push-notification lifecycle: permission prompt,
/// FCM/APNs token acquisition, backend registration/removal, and routing
/// of foreground / tapped messages.
///
/// Registered as a DI singleton. Driven by the auth lifecycle:
/// [registerForCurrentUser] after login, [unregister] on logout. Tapped
/// messages are forwarded to [onMessageTapped] (wired to
/// `PushNavigationCubit` in `app.dart`).
class PushNotificationService {
  PushNotificationService({
    required PushTokenRemoteDatasource datasource,
    required FlutterSecureStorage secureStorage,
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  })  : _datasource = datasource,
        _secureStorage = secureStorage,
        _messaging = messaging ?? FirebaseMessaging.instance,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin();

  final PushTokenRemoteDatasource _datasource;
  final FlutterSecureStorage _secureStorage;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;

  /// Secure-storage key for the backend-issued push-token record id.
  /// Stored so we can `DELETE /api/push-tokens/{id}` on logout. This is
  /// an opaque record id, not key material.
  static const _tokenIdKey = 'push_token_record_id';

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  bool _streamsBound = false;

  /// Callback invoked when the user taps a notification (background,
  /// terminated, or cold start). Set by `app.dart` to forward into
  /// `PushNavigationCubit`. Foreground taps on the local banner also
  /// route through here.
  void Function(PushMessage message)? onMessageTapped;

  /// Wires foreground/tap listeners and the local-notifications plugin.
  /// Idempotent — safe to call on every login.
  ///
  /// Does NOT request permission or register a token; call
  /// [registerForCurrentUser] for that after the user is authenticated.
  Future<void> init() async {
    if (_streamsBound) return;

    await _initLocalNotifications();

    // Foreground: the OS does NOT show a banner automatically, so render
    // one via flutter_local_notifications (Android) — iOS shows it via
    // the presentation options set below.
    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // App in background and brought to foreground by a notification tap.
    _openedAppSub =
        FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);

    // iOS: show the banner while in foreground.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _streamsBound = true;
    AppLogger.d('Push', 'Messaging streams bound');
  }

  /// Requests notification permission (iOS prompt / Android 13+
  /// POST_NOTIFICATIONS), obtains the FCM token, registers it with the
  /// backend, and subscribes to token-refresh for re-registration.
  ///
  /// Call after the user is authenticated. No-op-safe if permission is
  /// denied — the app simply won't receive pushes.
  Future<void> registerForCurrentUser() async {
    await init();

    final settings = await _messaging.requestPermission();
    AppLogger.i(
      'Push',
      'Permission status: ${settings.authorizationStatus.name}',
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    // On iOS the FCM token is only available once APNs has assigned a
    // device token; firebase_messaging handles that handshake internally.
    final token = await _messaging.getToken();
    if (token == null) {
      AppLogger.w('Push', 'FCM token unavailable, skipping registration');
      return;
    }

    await _registerToken(token);

    _tokenRefreshSub ??= _messaging.onTokenRefresh.listen((newToken) {
      AppLogger.i('Push', 'Token refreshed, re-registering');
      _registerToken(newToken);
    });
  }

  /// Removes the backend token record and deletes the local FCM token.
  /// Best-effort: tolerates network failure so logout always completes.
  Future<void> unregister() async {
    final id = await _secureStorage.read(key: _tokenIdKey);
    if (id != null && id.isNotEmpty) {
      try {
        await _datasource.deleteToken(id);
      } catch (e) {
        AppLogger.w('Push', 'Token delete failed (best-effort): $e');
      }
      await _secureStorage.delete(key: _tokenIdKey);
    }

    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    try {
      await _messaging.deleteToken();
    } catch (e) {
      AppLogger.w('Push', 'deleteToken failed (best-effort): $e');
    }
    AppLogger.i('Push', 'Push unregistered');
  }

  /// Returns the [PushMessage] that cold-started the app via a tap, or
  /// `null` if the app was launched normally. Call once after the router
  /// is ready so the initial deep-link fires.
  Future<PushMessage?> initialMessage() async {
    final message = await _messaging.getInitialMessage();
    if (message == null) return null;
    return _toPushMessage(message);
  }

  /// Disposes all stream subscriptions. Call from app teardown / tests.
  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedAppSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _foregroundSub = null;
    _openedAppSub = null;
    _tokenRefreshSub = null;
    _streamsBound = false;
  }

  Future<void> _registerToken(String token) async {
    try {
      final id = await _datasource.registerToken(
        token: token,
        platform: Platform.isIOS ? PushPlatform.ios : PushPlatform.android,
        deviceName: await _deviceName(),
      );
      await _secureStorage.write(key: _tokenIdKey, value: id);
      AppLogger.i('Push', 'Token registered with backend');
    } catch (e) {
      // Registration is non-fatal — the user can still use the app, they
      // just won't get pushes until the next refresh/login.
      AppLogger.w('Push', 'Token registration failed: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      // We request permission via FirebaseMessaging.requestPermission,
      // so don't prompt again here.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  void _onForegroundMessage(RemoteMessage message) {
    AppLogger.d('Push', 'Foreground message: type=${message.data['type']}');
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Carry the type so a tap on the foreground banner can route.
      payload: message.data['type'] as String?,
    );
  }

  void _onMessageOpened(RemoteMessage message) {
    onMessageTapped?.call(_toPushMessage(message));
  }

  void _onLocalNotificationTapped(NotificationResponse response) {
    // Foreground-banner tap: we only carried `type` in the payload, so
    // build a minimal message. Id-specific deep links come through the
    // background path which has the full data map.
    final type = response.payload;
    if (type == null) return;
    onMessageTapped?.call(
      PushMessage.fromData(<String, dynamic>{'type': type}),
    );
  }

  PushMessage _toPushMessage(RemoteMessage message) {
    return PushMessage.fromData(
      message.data,
      title: message.notification?.title,
      body: message.notification?.body,
    );
  }

  Future<String?> _deviceName() async {
    // Keep it cheap and dependency-free — a coarse platform label is
    // enough for the user to identify the device in the web panel.
    if (Platform.isIOS) return 'iOS device';
    if (Platform.isAndroid) return 'Android device';
    return null;
  }
}
