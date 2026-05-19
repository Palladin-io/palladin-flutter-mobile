import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/agent.dart';
import '../../domain/exceptions/agents_exceptions.dart';
import '../../domain/repositories/agents_repository.dart';
import '../datasources/agents_remote_data_source.dart';

/// Concrete implementation of [AgentsRepository].
///
/// Wraps [AgentsRemoteDataSource] and translates DioExceptions into
/// typed [AgentsException]s with semantic [AgentsErrorKind] values so the
/// presentation layer can render localized error messages.
class AgentsRepositoryImpl implements AgentsRepository {
  AgentsRepositoryImpl(this._dataSource);

  final AgentsRemoteDataSource _dataSource;

  @override
  Future<List<Agent>> listAgents() async {
    try {
      AppLogger.d('Agents', 'GET /api/agents');
      final models = await _dataSource.listAgents();
      return models.map((m) => m.toEntity()).toList(growable: false);
    } on DioException catch (e, s) {
      AppLogger.e('Agents', 'listAgents failed', error: e, stackTrace: s);
      throw AgentsException(_classifyError(e));
    }
  }

  @override
  Future<Agent> getAgent(String agentId) async {
    try {
      AppLogger.d('Agents', 'GET /api/agents/$agentId');
      final model = await _dataSource.getAgent(agentId);
      return model.toEntity();
    } on DioException catch (e, s) {
      AppLogger.e('Agents', 'getAgent failed', error: e, stackTrace: s);
      throw AgentsException(_classifyError(e));
    }
  }

  @override
  Future<void> approveAgent(String agentId) async {
    try {
      AppLogger.d('Agents', 'POST /api/agents/$agentId/approve');
      await _dataSource.approveAgent(agentId);
    } on DioException catch (e, s) {
      AppLogger.e('Agents', 'approveAgent failed', error: e, stackTrace: s);
      throw AgentsException(_classifyError(e));
    }
  }

  @override
  Future<void> deactivateAgent(String agentId) async {
    try {
      AppLogger.d('Agents', 'POST /api/agents/$agentId/deactivate');
      await _dataSource.deactivateAgent(agentId);
    } on DioException catch (e, s) {
      AppLogger.e('Agents', 'deactivateAgent failed', error: e, stackTrace: s);
      throw AgentsException(_classifyError(e));
    }
  }

  @override
  Future<void> reactivateAgent(String agentId) async {
    try {
      AppLogger.d('Agents', 'POST /api/agents/$agentId/reactivate');
      await _dataSource.reactivateAgent(agentId);
    } on DioException catch (e, s) {
      AppLogger.e('Agents', 'reactivateAgent failed', error: e, stackTrace: s);
      throw AgentsException(_classifyError(e));
    }
  }

  @override
  Future<void> updateAgent(
    String agentId, {
    String? name,
    String? description,
  }) async {
    try {
      AppLogger.d('Agents', 'PATCH /api/agents/$agentId');
      await _dataSource.updateAgent(
        agentId,
        name: name,
        description: description,
      );
    } on DioException catch (e, s) {
      AppLogger.e('Agents', 'updateAgent failed', error: e, stackTrace: s);
      throw AgentsException(_classifyError(e));
    }
  }

  /// Maps a [DioException] to a typed [AgentsErrorKind].
  AgentsErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return AgentsErrorKind.networkError;
    }

    return switch (e.response?.statusCode) {
      404 => AgentsErrorKind.notFound,
      403 => AgentsErrorKind.forbidden,
      400 => AgentsErrorKind.validation,
      _ => AgentsErrorKind.unknown,
    };
  }
}
