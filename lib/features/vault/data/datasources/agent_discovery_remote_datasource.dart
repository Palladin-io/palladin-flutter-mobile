import 'package:dio/dio.dart';

import '../models/agent_discovery_provisioning.dart';

abstract interface class AgentDiscoveryRemote {
  Future<int> currentVdkVersion(String vaultId);
  Future<List<AgentDiscoveryProvisioning>> list(String vaultId);
}

final class AgentDiscoveryRemoteDatasource implements AgentDiscoveryRemote {
  AgentDiscoveryRemoteDatasource(this._dio);
  final Dio _dio;

  @override
  Future<int> currentVdkVersion(String vaultId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId',
    );
    final epoch = response.data?['currentKeyEpoch'];
    if (epoch is! Map || epoch['vdkVersion'] is! int) {
      throw const FormatException('Malformed Vault Discovery key epoch');
    }
    return epoch['vdkVersion'] as int;
  }

  @override
  Future<List<AgentDiscoveryProvisioning>> list(String vaultId) async {
    final result = <AgentDiscoveryProvisioning>[];
    String? afterId;
    do {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/vaults/$vaultId/discovery/agents',
        queryParameters: {'pageSize': 100, 'afterId': ?afterId},
      );
      final data = response.data;
      if (data == null || data['items'] is! List) {
        throw const FormatException('Malformed Discovery provisioning page');
      }
      result.addAll(
        (data['items'] as List).map(
          (item) => AgentDiscoveryProvisioning.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        ),
      );
      if (result.length > 2000) {
        throw StateError('Discovery provisioning exceeds mobile budget');
      }
      final next = data['nextAfterId'] as String?;
      if (next != null &&
          (next == afterId || (data['items'] as List).isEmpty)) {
        throw const FormatException('Non-advancing Discovery cursor');
      }
      afterId = next;
    } while (afterId != null);
    return List.unmodifiable(result);
  }
}
