import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/api_key.dart';
import '../../domain/entities/org.dart';
import '../../domain/exceptions/settings_exceptions.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_remote_data_source.dart';

/// Concrete implementation of [SettingsRepository].
///
/// Wraps [SettingsRemoteDataSource] and translates DioExceptions into
/// typed [SettingsException]s with semantic [SettingsErrorKind] values
/// so the presentation layer can render localized error messages.
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._dataSource);

  final SettingsRemoteDataSource _dataSource;

  @override
  Future<Org> getOrg() async {
    try {
      AppLogger.d('Settings', 'GET /api/org');
      final model = await _dataSource.getOrg();
      return model.toEntity();
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'getOrg failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  @override
  Future<void> updateOrgName(String name) async {
    try {
      AppLogger.d('Settings', 'PUT /api/org');
      await _dataSource.updateOrgName(name);
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'updateOrgName failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  @override
  Future<List<ApiKey>> listApiKeys() async {
    try {
      AppLogger.d('Settings', 'GET /api/api-keys');
      final models = await _dataSource.listApiKeys();
      return models.map((m) => m.toEntity()).toList(growable: false);
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'listApiKeys failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  @override
  Future<NewApiKey> createApiKey(String name) async {
    try {
      AppLogger.d('Settings', 'POST /api/api-keys');
      final model = await _dataSource.createApiKey(name);
      return model.toEntity();
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'createApiKey failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  @override
  Future<void> revokeApiKey(String keyId) async {
    try {
      AppLogger.d('Settings', 'DELETE /api/api-keys/$keyId');
      await _dataSource.revokeApiKey(keyId);
    } on DioException catch (e, s) {
      AppLogger.e('Settings', 'revokeApiKey failed', error: e, stackTrace: s);
      throw SettingsException(_classifyError(e));
    }
  }

  /// Maps a [DioException] to a typed [SettingsErrorKind].
  SettingsErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return SettingsErrorKind.networkError;
    }

    return switch (e.response?.statusCode) {
      404 => SettingsErrorKind.notFound,
      403 => SettingsErrorKind.forbidden,
      400 => SettingsErrorKind.validation,
      _ => SettingsErrorKind.unknown,
    };
  }
}
