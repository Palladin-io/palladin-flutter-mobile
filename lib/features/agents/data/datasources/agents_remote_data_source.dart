import 'package:dio/dio.dart';

import '../models/agent_model.dart';

/// Remote data source for the agent-management endpoints.
///
/// Communicates with the .NET backend at `/api/agents`. Returns DTOs —
/// domain mapping happens in the repository layer. DioExceptions surface
/// raw so the repository can classify error semantics (404 / 403 / 400 /
/// network) into typed `AgentsException`s.
class AgentsRemoteDataSource {
  AgentsRemoteDataSource(this._dio);

  final Dio _dio;

  /// `GET /api/agents` → list of agents for the organization.
  Future<List<AgentModel>> listAgents() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/agents');
    final data = response.data;
    if (data == null) {
      throw _emptyBody(response);
    }
    final raw = (data['items'] as List<dynamic>? ?? const <dynamic>[]);
    return raw
        .map((e) => AgentModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// `GET /api/agents/{agentId}` → a single agent.
  Future<AgentModel> getAgent(String agentId) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/agents/$agentId');
    final data = response.data;
    if (data == null) {
      throw _emptyBody(response);
    }
    return AgentModel.fromJson(data);
  }

  /// `POST /api/agents/{agentId}/approve` → 204 (no body).
  ///
  /// Optionally sets the agent's [name], [type] and [iconKey] at
  /// approval time. Only the keys present in the body are applied — a
  /// `null` argument is omitted so the server keeps its default.
  Future<void> approveAgent(
    String agentId, {
    String? name,
    String? type,
    String? iconKey,
  }) async {
    final body = <String, dynamic>{
      'name': ?name,
      'type': ?type,
      'iconKey': ?iconKey,
    };
    await _dio.post<void>('/api/agents/$agentId/approve', data: body);
  }

  /// `POST /api/agents/{agentId}/deactivate` → 200 (no body).
  Future<void> deactivateAgent(String agentId) async {
    await _dio.post<void>('/api/agents/$agentId/deactivate');
  }

  /// `POST /api/agents/{agentId}/reactivate` → 200 (no body).
  Future<void> reactivateAgent(String agentId) async {
    await _dio.post<void>('/api/agents/$agentId/reactivate');
  }

  /// `PATCH /api/agents/{agentId}` → 200 (no body).
  ///
  /// Only the keys present in the body are updated. A `null` [name] or
  /// [description] is omitted from the payload so it stays unchanged.
  Future<void> updateAgent(
    String agentId, {
    String? name,
    String? description,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    await _dio.patch<void>('/api/agents/$agentId', data: body);
  }

  DioException _emptyBody(Response<dynamic> response) => DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
}
