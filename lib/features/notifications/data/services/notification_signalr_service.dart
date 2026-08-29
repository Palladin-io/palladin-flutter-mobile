import 'package:signalr_netcore/signalr_client.dart';

import '../../../../config/env_config.dart';
import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/push_message.dart';

/// Value-free hint that a Vault's authoritative Member stream advanced.
final class VaultSyncInvalidation {
  const VaultSyncInvalidation({
    required this.vaultId,
    required this.memberSequence,
    required this.mutationVersion,
    required this.removed,
  });

  factory VaultSyncInvalidation.fromJson(Map<String, dynamic> json) {
    const fields = {
      'protocolVersion',
      'vaultId',
      'memberSequence',
      'mutationVersion',
      'removed',
    };
    final vaultId = json['vaultId'];
    final memberSequence = json['memberSequence'];
    final mutationVersion = json['mutationVersion'];
    final removed = json['removed'];
    final decimal = RegExp(r'^(?:0|[1-9][0-9]*)$');
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    const maximumUint64 = '18446744073709551615';
    bool canonicalUint64(Object? value) {
      if (value is! String || !decimal.hasMatch(value)) return false;
      return value.length < maximumUint64.length ||
          (value.length == maximumUint64.length &&
              value.compareTo(maximumUint64) <= 0);
    }

    if (json.keys.toSet().difference(fields).isNotEmpty ||
        !json.keys.toSet().containsAll(fields) ||
        json['protocolVersion'] != 1 ||
        vaultId is! String ||
        !uuid.hasMatch(vaultId) ||
        !canonicalUint64(memberSequence) ||
        !canonicalUint64(mutationVersion) ||
        removed is! bool) {
      throw const FormatException('Malformed Vault sync invalidation');
    }
    return VaultSyncInvalidation(
      vaultId: vaultId,
      memberSequence: memberSequence,
      mutationVersion: mutationVersion,
      removed: removed,
    );
  }

  final String vaultId;
  final String memberSequence;
  final String mutationVersion;
  final bool removed;
}

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

  /// Invoked for structural Vault invalidations only. Ciphertext is repaired
  /// through authenticated REST by the application lifecycle coordinator.
  void Function(VaultSyncInvalidation invalidation)? onVaultSyncInvalidation;

  /// Invoked after automatic transport reconnection to request a full repair.
  void Function()? onReconnected;

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
    connection.on('ReceiveVaultSyncInvalidation', _handleVaultSyncInvalidation);
    connection.onreconnected(({connectionId}) => onReconnected?.call());

    try {
      await connection.start();
      // Only retain the connection after a successful start — otherwise a
      // failed start (offline, 401) would leave `_connection != null`, and
      // the early-return above would permanently block any reconnect attempt.
      _connection = connection;
      AppLogger.i('SignalR', 'Connected to $_hubUrl');
    } catch (_) {
      AppLogger.w('SignalR', 'Connect failed (best-effort)');
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
    } catch (_) {
      AppLogger.w('SignalR', 'Disconnect failed (best-effort)');
    }
  }

  void _handleNotification(List<Object?>? arguments) {
    // arguments: [type (String), payload (Map: type/title/body/data/timestamp)]
    if (arguments == null || arguments.isEmpty) return;

    final typeFromArg = arguments[0] is String ? arguments[0] as String : null;
    final payload = arguments.length > 1 ? arguments[1] : null;

    final data = <String, dynamic>{};
    String? type = typeFromArg;
    if (payload is Map) {
      type ??= payload['type'] as String?;
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
    final message = PushMessage.fromData({...data, 'type': type});
    if (message == null) return;
    AppLogger.d('SignalR', 'Structural notification received');
    onNotification?.call(message);
  }

  void _handleVaultSyncInvalidation(List<Object?>? arguments) {
    if (arguments == null ||
        arguments.length != 1 ||
        arguments.single is! Map) {
      return;
    }
    try {
      final invalidation = VaultSyncInvalidation.fromJson(
        Map<String, dynamic>.from(arguments.single! as Map),
      );
      AppLogger.d('SignalR', 'Vault sync invalidation received');
      onVaultSyncInvalidation?.call(invalidation);
    } on FormatException {
      AppLogger.w('SignalR', 'Malformed Vault sync invalidation ignored');
    }
  }
}
