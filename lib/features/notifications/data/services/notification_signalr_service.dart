import 'package:signalr_netcore/signalr_client.dart';

import '../../../../config/env_config.dart';
import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/push_message.dart';

/// In-app real-time channel — connects to the backend SignalR hub
/// (`/hubs/notifications`) while the app is in the foreground, mirroring the
/// web panel. This is the mobile equivalent of the web's live updates: it
/// delivers notifications instantly over a WebSocket and, crucially, works on
/// the iOS simulator (no APNs needed). FCM/APNs remains the background channel.
///
/// The hub method is `ReceiveNotification(type, payload)` — same contract as
/// the web client. The JWT is supplied via `accessTokenFactory`, appended as
/// `?access_token=` for the WebSocket transport.
class NotificationSignalRService {
  NotificationSignalRService({
    required this.config,
    required this.tokenStorage,
  });

  final EnvConfig config;
  final SecureTokenStorage tokenStorage;

  HubConnection? _connection;

  /// Invoked for every notification received over the hub — wired in
  /// `app.dart` to refresh the affected list (agents / grants) live.
  void Function(PushMessage message)? onNotification;

  String get _hubUrl => '${config.apiBaseUrl}/hubs/notifications';

  /// Opens the hub connection (idempotent). Best-effort: a failed start is
  /// logged, not thrown — the app still works via on-focus / resume refresh
  /// and background push.
  Future<void> connect() async {
    if (_connection != null) return;

    final connection = HubConnectionBuilder()
        .withUrl(
          _hubUrl,
          options: HttpConnectionOptions(
            accessTokenFactory: () async =>
                (await tokenStorage.accessToken) ?? '',
          ),
        )
        .withAutomaticReconnect()
        .build();

    connection.on('ReceiveNotification', _handleNotification);

    try {
      await connection.start();
      // Only retain the connection after a successful start — otherwise a
      // failed start (offline, 401) would leave `_connection != null`, and
      // the early-return above would permanently block any reconnect attempt.
      _connection = connection;
      AppLogger.i('SignalR', 'Connected to $_hubUrl');
    } catch (e) {
      AppLogger.w('SignalR', 'Connect failed (best-effort): $e');
    }
  }

  /// Closes the connection (on logout / teardown). Safe to call when not
  /// connected.
  Future<void> disconnect() async {
    final connection = _connection;
    _connection = null;
    if (connection == null) return;
    try {
      await connection.stop();
      AppLogger.i('SignalR', 'Disconnected');
    } catch (e) {
      AppLogger.w('SignalR', 'Disconnect failed (best-effort): $e');
    }
  }

  void _handleNotification(List<Object?>? arguments) {
    // arguments: [type (String), payload (Map: type/title/body/data/timestamp)]
    if (arguments == null || arguments.isEmpty) return;

    final typeFromArg = arguments[0] is String ? arguments[0] as String : null;
    final payload = arguments.length > 1 ? arguments[1] : null;

    final data = <String, dynamic>{};
    String? type = typeFromArg;
    String? title;
    String? body;
    if (payload is Map) {
      type ??= payload['type'] as String?;
      title = payload['title'] as String?;
      body = payload['body'] as String?;
      final rawData = payload['data'];
      if (rawData is Map) {
        rawData.forEach((key, value) {
          if (value != null) data['$key'] = value;
        });
      }
    }
    if (type == null) return;

    // Reuse the same mapping as FCM (type lives at the top level here, so we
    // fold it into the data map that PushMessage.fromData reads). Title/body
    // are carried through so the app can surface a visible in-app banner —
    // SignalR has no OS-level notification of its own (unlike FCM).
    final message = PushMessage.fromData(
      {...data, 'type': type},
      title: title,
      body: body,
    );
    AppLogger.d('SignalR', 'Notification: ${message.type.name}');
    onNotification?.call(message);
  }
}
