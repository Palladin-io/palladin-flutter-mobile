import 'package:dio/dio.dart';

import '../models/inbox_notification_model.dart';
import '../models/notification_preference_model.dart';

/// Remote data source for the Notification Center (frozen contract, JWT,
/// self-scoped).
///
/// Endpoints:
/// - `GET  /api/notifications?cursor&limit&category?&unreadOnly?`
/// - `GET  /api/notifications/summary`
/// - `PUT  /api/notifications/{id}/read`
/// - `PUT  /api/notifications/read-all`
/// - `GET  /api/notifications/preferences`
/// - `PUT  /api/notifications/preferences`
class NotificationCenterRemoteDatasource {
  NotificationCenterRemoteDatasource(this._dio);

  final Dio _dio;

  Future<({List<InboxNotificationModel> items, String? nextCursor})> list({
    String? cursor,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/notifications',
      queryParameters: <String, dynamic>{'cursor': ?cursor},
    );
    final data = response.data ?? const <String, dynamic>{};
    final rawItems = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return (
      items: rawItems
          .map(
            (item) => InboxNotificationModel.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      nextCursor: data['nextCursor'] as String?,
    );
  }

  Future<({int unreadCount, int pendingActionCount})> summary() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/notifications/summary',
    );
    final data = response.data ?? const <String, dynamic>{};
    return (
      unreadCount: data['unreadCount'] as int? ?? 0,
      pendingActionCount: data['pendingActionCount'] as int? ?? 0,
    );
  }

  Future<void> markRead(String id) =>
      _dio.put<void>('/api/notifications/$id/read');

  Future<void> markAllRead() => _dio.put<void>('/api/notifications/read-all');

  Future<List<NotificationPreferenceModel>> preferences() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/notifications/preferences',
    );
    final data = response.data ?? const <String, dynamic>{};
    final rawItems = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return rawItems
        .map(
          (item) => NotificationPreferenceModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  /// Upserts the deltas for one type+channel and returns the effective state.
  /// The backend ignores inbox/realtime changes on mandatory types.
  Future<List<NotificationPreferenceModel>> updatePreferences({
    required String type,
    bool? inboxEnabled,
    bool? signalREnabled,
    bool? pushEnabled,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/notifications/preferences',
      data: <String, dynamic>{
        'items': [
          <String, dynamic>{
            'type': type,
            'inboxEnabled': ?inboxEnabled,
            'signalREnabled': ?signalREnabled,
            'pushEnabled': ?pushEnabled,
          },
        ],
      },
    );
    final data = response.data ?? const <String, dynamic>{};
    final rawItems = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return rawItems
        .map(
          (item) => NotificationPreferenceModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }
}
