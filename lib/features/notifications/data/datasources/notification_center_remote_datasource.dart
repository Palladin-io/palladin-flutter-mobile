import 'package:dio/dio.dart';

import '../models/inbox_notification_model.dart';

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

  Future<({int unreadCount, int openActionRequiredCount})> summary() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/notifications/summary',
    );
    final data = response.data ?? const <String, dynamic>{};
    return (
      unreadCount: data['unreadCount'] as int? ?? 0,
      openActionRequiredCount: data['openActionRequiredCount'] as int? ?? 0,
    );
  }

  Future<void> markRead(String id) =>
      _dio.put<void>('/api/notifications/$id/read');

  Future<void> markAllRead() => _dio.put<void>('/api/notifications/read-all');
}
