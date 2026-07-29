import 'package:dio/dio.dart';

import '../models/agent_model.dart';

/// Presigned S3 upload + public URL pair returned by the icon presign endpoint.
class AgentPresignResponse {
  const AgentPresignResponse({
    required this.uploadUrl,
    required this.assetId,
    required this.uploadSessionId,
    required this.maximumBytes,
  });

  final String uploadUrl;
  final String assetId;
  final String uploadSessionId;
  final int maximumBytes;
}

class AgentIconCompleteResponse {
  const AgentIconCompleteResponse({required this.assetId});
  final String assetId;
}

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
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/agents/$agentId',
    );
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
    String? iconColor,
  }) async {
    final body = <String, dynamic>{
      'name': ?name,
      'type': ?type,
      'iconKey': ?iconKey,
      'iconColor': ?iconColor,
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
  /// Only the keys present in the body are updated. A `null` argument is
  /// omitted from the payload so that field stays unchanged on the server.
  Future<void> updateAgent(
    String agentId, {
    String? name,
    String? description,
    String? type,
    String? iconKey,
    String? iconColor,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (type != null) body['type'] = type;
    if (iconKey != null) body['iconKey'] = iconKey;
    if (iconColor != null) body['iconColor'] = iconColor;
    await _dio.patch<void>('/api/agents/$agentId', data: body);
  }

  /// `POST /api/agents/{agentId}/icon/presign` → presigned S3 upload URL.
  ///
  /// Returns an [AgentPresignResponse] with an `uploadUrl` for the S3 PUT
  /// and a `publicUrl` to store as `iconKey` after the upload completes.
  Future<AgentPresignResponse> presignAgentIcon(
    String agentId, {
    required String mediaType,
    required int byteLength,
    required String sha256,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/agents/$agentId/icon/presign',
      data: {
        'agentId': agentId,
        'mediaType': mediaType,
        'byteLength': byteLength,
        'sha256': sha256,
      },
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    return AgentPresignResponse(
      uploadUrl: data['uploadUrl'] as String,
      assetId: data['assetId'] as String,
      uploadSessionId: data['uploadSessionId'] as String,
      maximumBytes: (data['maximumBytes'] as num).toInt(),
    );
  }

  Future<AgentIconCompleteResponse> completeAgentIcon(
    String agentId,
    String uploadSessionId,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/agents/$agentId/icon/complete',
      data: {'agentId': agentId, 'uploadSessionId': uploadSessionId},
    );
    final data = response.data;
    if (data == null) throw _emptyBody(response);
    return AgentIconCompleteResponse(assetId: data['assetId'] as String);
  }

  DioException _emptyBody(Response<dynamic> response) => DioException(
    requestOptions: response.requestOptions,
    response: response,
    type: DioExceptionType.badResponse,
    error: 'Empty response body',
  );
}
