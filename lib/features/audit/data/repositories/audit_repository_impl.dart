import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/exceptions/audit_exceptions.dart';
import '../../domain/repositories/audit_repository.dart';
import '../datasources/audit_remote_datasource.dart';

/// Concrete implementation of [AuditRepository].
///
/// Wraps [AuditRemoteDatasource] and translates DioExceptions into typed
/// [AuditException]s so the presentation layer can render localized
/// errors. Maps DTOs to domain entities at the boundary.
class AuditRepositoryImpl implements AuditRepository {
  AuditRepositoryImpl(this._dataSource);

  final AuditRemoteDatasource _dataSource;

  @override
  Future<AuditLogPage> listVaultLogs(
    String vaultId, {
    String? cursor,
    int pageSize = 50,
  }) async {
    try {
      AppLogger.d('Audit', 'GET /api/vaults/$vaultId/audit-logs');
      final page = await _dataSource.listVaultLogs(
        vaultId,
        cursor: cursor,
        pageSize: pageSize,
      );
      return AuditLogPage(
        entries: page.items.map((m) => m.toEntity()).toList(growable: false),
        nextCursor: page.nextCursor,
      );
    } on DioException catch (e, s) {
      AppLogger.e('Audit', 'listVaultLogs failed', error: e, stackTrace: s);
      throw AuditException(_classifyError(e));
    }
  }

  /// Maps a [DioException] to a typed [AuditErrorKind].
  AuditErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return AuditErrorKind.networkError;
    }

    return switch (e.response?.statusCode) {
      403 => AuditErrorKind.forbidden,
      404 => AuditErrorKind.notFound,
      _ => AuditErrorKind.unknown,
    };
  }
}
