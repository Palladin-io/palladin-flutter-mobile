import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
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
  'palladin_default',
  'Palladin',
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
    DeviceInfoPlugin? deviceInfo,
  })  : _datasource = datasource,
        _secureStorage = secureStorage,
        _messaging = messaging ?? FirebaseMessaging.instance,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final PushTokenRemoteDatasource _datasource;
  final FlutterSecureStorage _secureStorage;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final DeviceInfoPlugin _deviceInfo;

  /// Monotonic counter for the local-notification id — id must fit a Java
  /// `int` (32-bit signed) on Android, and `Object.hash()` does not. A
  /// per-instance counter is both in-range and collision-free.
  int _localNotificationSeq = 0;

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

  /// Invoked for every **foreground** push as it arrives (not on tap). Set by
  /// `app.dart` to refresh the relevant list (agents / grants) so the in-app
  /// data stays live — mobile's equivalent of the web panel's SignalR
  /// invalidation. Tap-routing still goes through [onMessageTapped].
  void Function(PushMessage message)? onMessageReceived;

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

    // On iOS the FCM token is only available once APNs has assigned a device
    // token. On the simulator (and before APNs registers) there is no APNs
    // token and getToken() throws [apns-token-not-set] — guard so we skip
    // registration cleanly instead of throwing an unhandled exception.
    if (Platform.isIOS) {
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken == null) {
        AppLogger.w(
          'Push',
          'APNs token unavailable (e.g. simulator), skipping FCM registration',
        );
        return;
      }
    }

    final String? token;
    try {
      token = await _messaging.getToken();
    } catch (e) {
      AppLogger.w('Push', 'getToken failed, skipping registration: $e');
      return;
    }
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
    // Refresh the relevant in-app list first (works for data-only messages
    // too) — mobile's equivalent of the web's live SignalR refresh.
    onMessageReceived?.call(_toPushMessage(message));

    final notification = message.notification;
    if (notification == null) return;

    showLocalNotification(
      title: notification.title,
      body: notification.body,
      data: message.data,
    );
  }

  /// Shows an OS-level heads-up notification while the app is foregrounded.
  ///
  /// Used both by FCM foreground messages and by the SignalR channel — the
  /// latter has no OS notification of its own, so without this a real-time
  /// event would update lists silently with nothing visible to the user
  /// (the web shows a toast for the same events). No-op when both title and
  /// body are empty.
  ///
  /// [data] is the full notification data map (type + ids) — JSON-encoded
  /// into the payload so a tap on the banner can deep-link to the specific
  /// agent / grant (not just the list). Callers that have only the type
  /// can pass `{'type': type}`.
  void showLocalNotification({
    String? title,
    String? body,
    Map<String, dynamic>? data,
    @Deprecated('Pass data: {"type": type} instead so deep-link ids survive.')
    String? type,
  }) {
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }
    final payloadMap = data ?? (type != null ? {'type': type} : null);
    _localNotifications.show(
      _nextLocalNotificationId(),
      title,
      body,
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
      // JSON-encoded data so a tap on the foreground banner preserves
      // grantId / agentId and the deep-link lands on the specific entity
      // (not just the agents list).
      payload: payloadMap != null ? jsonEncode(payloadMap) : null,
    );
  }

  /// Produces a deterministic, in-range id for the local notification.
  ///
  /// `flutter_local_notifications` requires a Java `int` (32-bit signed) on
  /// Android — `Object.hash(...)` may exceed that. A monotonic counter is
  /// trivially in-range and avoids any collision risk.
  int _nextLocalNotificationId() {
    _localNotificationSeq = (_localNotificationSeq + 1) & 0x7fffffff;
    return _localNotificationSeq;
  }

  void _onMessageOpened(RemoteMessage message) {
    onMessageTapped?.call(_toPushMessage(message));
  }

  void _onLocalNotificationTapped(NotificationResponse response) {
    // Foreground-banner tap: decode the JSON payload we wrote in
    // [showLocalNotification] so the full data map (type + grantId /
    // agentId) survives and the deep-link can land on the specific entity.
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;
    onMessageTapped?.call(PushMessage.fromData(_decodePayload(raw)));
  }

  /// Decodes a local-notification payload back to a routing data map. Falls
  /// back to a `{type: raw}` map for legacy (pre-JSON) payloads that may
  /// still be sitting in the OS tray after upgrade.
  Map<String, dynamic> _decodePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    } catch (_) {
      // fallthrough
    }
    return <String, dynamic>{'type': raw};
  }

  PushMessage _toPushMessage(RemoteMessage message) {
    return PushMessage.fromData(
      message.data,
      title: message.notification?.title,
      body: message.notification?.body,
    );
  }

  Future<String?> _deviceName() async {
    // Use the real device identifier (e.g. "iPhone 15", "Pixel 8") so the
    // user can tell their devices apart in the web panel — far more useful
    // than the previous hardcoded "iOS device" / "Android device" labels,
    // and avoids leaking the mobile UI locale into a string the web shows.
    try {
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        final name = info.name.trim();
        final model = info.utsname.machine.trim();
        if (name.isNotEmpty) return name;
        if (model.isNotEmpty) return model;
        return 'iOS device';
      }
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        final manufacturer = info.manufacturer.trim();
        final model = info.model.trim();
        if (manufacturer.isNotEmpty && model.isNotEmpty) {
          return '$manufacturer $model';
        }
        if (model.isNotEmpty) return model;
        return 'Android device';
      }
    } catch (e) {
      AppLogger.w('Push', 'device_info lookup failed: $e');
    }
    return null;
  }
}
