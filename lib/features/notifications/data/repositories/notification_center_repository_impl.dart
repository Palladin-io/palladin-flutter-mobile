import 'package:dio/dio.dart';

import '../../domain/entities/inbox_notification.dart';
import '../../domain/exceptions/notification_center_exceptions.dart';
import '../../domain/repositories/notification_center_repository.dart';
import '../datasources/notification_center_remote_datasource.dart';

class NotificationCenterRepositoryImpl implements NotificationCenterRepository {
  NotificationCenterRepositoryImpl(this._datasource);

  final NotificationCenterRemoteDatasource _datasource;

  @override
  Future<NotificationPage> list({String? cursor}) async {
    try {
      final page = await _datasource.list(cursor: cursor);
      return NotificationPage(
        items: page.items
            .map((item) => item.toEntity())
            .toList(growable: false),
        nextCursor: page.nextCursor,
      );
    } on DioException catch (error) {
      throw NotificationCenterException(_classify(error));
    }
  }

  @override
  Future<NotificationSummary> summary() async {
    try {
      final summary = await _datasource.summary();
      return NotificationSummary(
        unreadCount: summary.unreadCount,
        openActionRequiredCount: summary.openActionRequiredCount,
      );
    } on DioException catch (error) {
      throw NotificationCenterException(_classify(error));
    }
  }

  @override
  Future<void> markRead(String id) async {
    try {
      await _datasource.markRead(id);
    } on DioException catch (error) {
      throw NotificationCenterException(_classify(error));
    }
  }

  @override
  Future<void> markAllRead() async {
    try {
      await _datasource.markAllRead();
    } on DioException catch (error) {
      throw NotificationCenterException(_classify(error));
    }
  }

  NotificationCenterErrorKind _classify(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return NotificationCenterErrorKind.forbidden;
    }
    if (status != null && status >= 500) {
      return NotificationCenterErrorKind.serverError;
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return NotificationCenterErrorKind.networkError;
    }
    return NotificationCenterErrorKind.unknown;
  }
}
