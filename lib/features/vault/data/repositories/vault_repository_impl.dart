import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../autofill/data/autofill_mutation_notifier.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../../domain/repositories/vault_repository.dart';
import '../datasources/vault_remote_datasource.dart';

/// Concrete implementation of [VaultRepository].
///
/// Wraps [VaultRemoteDatasource] and translates DioExceptions into
/// typed [VaultException]s with semantic [VaultErrorKind] values so
/// the presentation layer can render localized error messages.
class VaultRepositoryImpl implements VaultRepository {
  VaultRepositoryImpl(this._datasource, {this.autoFillMutationNotifier});

  final VaultRemoteDatasource _datasource;
  final AutoFillMutationNotifier? autoFillMutationNotifier;

  @override
  Future<void> deleteVault(String id) async {
    try {
      AppLogger.d('Vault', 'DELETE /api/vaults/$id');
      await _datasource.deleteVault(id);
      await autoFillMutationNotifier?.notifyChanged();
    } on DioException catch (e, s) {
      AppLogger.e('Vault', 'deleteVault failed', error: e, stackTrace: s);
      throw VaultException(_classifyError(e));
    }
  }

  /// Maps a [DioException] to a typed [VaultErrorKind].
  ///
  /// 403 responses are inspected to disambiguate plan-limit and
  /// full-mode-not-allowed errors via the `errorCode` / `code` field
  /// returned by the .NET API. Falls back to plain [VaultErrorKind.forbidden]
  /// when the body has no machine-readable hint.
  VaultErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return VaultErrorKind.networkError;
    }

    final status = e.response?.statusCode;
    if (status == 404) {
      return VaultErrorKind.notFound;
    }
    if (status == 403) {
      final code = _extractErrorCode(e.response?.data);
      if (code == null) return VaultErrorKind.forbidden;
      if (code.contains('plan') && code.contains('limit')) {
        return VaultErrorKind.planLimitReached;
      }
      if (code.contains('full') && code.contains('mode')) {
        return VaultErrorKind.fullModeNotAllowed;
      }
      return VaultErrorKind.forbidden;
    }

    return VaultErrorKind.unknown;
  }

  /// Extracts a normalized lowercase error code from a 403 response
  /// body. Backend conventions vary — checks both `errorCode` and
  /// `code` and falls back to a `message` substring scan so the
  /// classification is resilient to small backend changes.
  String? _extractErrorCode(dynamic body) {
    if (body is Map<String, dynamic>) {
      final code = body['errorCode'] ?? body['code'] ?? body['error'];
      if (code is String) return code.toLowerCase();
      final message = body['message'] ?? body['detail'];
      if (message is String) return message.toLowerCase();
    }
    if (body is String) return body.toLowerCase();
    return null;
  }
}
