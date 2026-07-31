import 'package:dio/dio.dart';

import '../models/vault_rotation_models.dart';

final class RotationCommitResult {
  const RotationCommitResult({required this.committed});
  final bool committed;
}

/// Bounded REST client for the staged Vault rotation protocol.
class VaultRotationRemoteDatasource {
  VaultRotationRemoteDatasource(this._dio);
  final Dio _dio;

  Future<List<VaultRotationModel>> listPending(CancelToken cancelToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vault-key-rotations/pending',
      cancelToken: cancelToken,
    );
    final items = _body(response)['items'];
    if (items is! List || items.length > 200) {
      throw const FormatException('Pending rotation list exceeds limit');
    }
    return items
        .map(
          (item) => VaultRotationModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<VaultRotationClaimModel> claim(
    String vaultId,
    String rotationId,
    CancelToken cancelToken,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/key-rotations/$rotationId/claim',
      data: {'vaultId': vaultId, 'rotationId': rotationId},
      cancelToken: cancelToken,
    );
    return VaultRotationClaimModel.fromJson(_body(response));
  }

  Future<RotationPage<RotationMemberRecipient>> members(
    String vaultId,
    String rotationId,
    String fencingToken,
    String? afterId,
    CancelToken cancelToken,
  ) => _sourcePage(
    '/api/vaults/$vaultId/key-rotations/$rotationId/source/members',
    fencingToken,
    afterId,
    null,
    cancelToken,
    RotationMemberRecipient.fromJson,
  );

  Future<RotationPage<Map<String, dynamic>>> entryKeys(
    String vaultId,
    String rotationId,
    String fencingToken,
    String? afterId,
    int? afterVersion,
    CancelToken cancelToken,
  ) => _sourcePage(
    '/api/vaults/$vaultId/key-rotations/$rotationId/source/entry-keys',
    fencingToken,
    afterId,
    afterVersion,
    cancelToken,
    (json) => json,
  );

  Future<RotationPage<RotationDiscoverySource>> discoveries(
    String vaultId,
    String rotationId,
    String fencingToken,
    String? afterId,
    CancelToken cancelToken,
  ) => _sourcePage(
    '/api/vaults/$vaultId/key-rotations/$rotationId/source/discoveries',
    fencingToken,
    afterId,
    null,
    cancelToken,
    RotationDiscoverySource.fromJson,
  );

  Future<RotationPage<RotationAgentRecipient>> agents(
    String vaultId,
    String? afterId,
    CancelToken cancelToken,
  ) => _sourcePage(
    '/api/vaults/$vaultId/discovery/agents',
    null,
    afterId,
    null,
    cancelToken,
    RotationAgentRecipient.fromJson,
  );

  Future<Map<String, dynamic>> vaultMetadata(
    String vaultId,
    CancelToken cancelToken,
  ) async {
    var offset = 0;
    while (true) {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/vaults',
        queryParameters: {'limit': 200, 'offset': offset},
        cancelToken: cancelToken,
      );
      final body = _body(response);
      final vaults = body['vaults'];
      final total = body['total'];
      if (vaults is! List || total is! int || vaults.length > 200) {
        throw const FormatException('Malformed Vault metadata page');
      }
      for (final raw in vaults) {
        final vault = Map<String, dynamic>.from(raw as Map);
        if (vault['id'] == vaultId) {
          final metadata = vault['memberVaultMetadata'];
          if (metadata is! Map) {
            throw const FormatException('Vault metadata envelope is missing');
          }
          return Map<String, dynamic>.from(metadata);
        }
      }
      offset += vaults.length;
      if (vaults.isEmpty || offset >= total) {
        throw StateError('Vault metadata not found');
      }
    }
  }

  Future<void> prepare(
    String vaultId,
    String rotationId,
    String fencingToken,
    Map<String, dynamic> batch,
    CancelToken cancelToken,
  ) async {
    final data = <String, dynamic>{
      'vaultId': vaultId,
      'rotationId': rotationId,
      'fencingToken': fencingToken,
      'memberVaultKeys': const <dynamic>[],
      'entryKeys': const <dynamic>[],
      'entryDiscoveries': const <dynamic>[],
      'agentDiscoveries': const <dynamic>[],
      'vaultPrivateKeys': const <dynamic>[],
      ...batch,
    };
    final count =
        [
          data['memberVaultMetadata'],
          data['discoveryKey'],
        ].where((item) => item != null).length +
        [
          'memberVaultKeys',
          'entryKeys',
          'entryDiscoveries',
          'agentDiscoveries',
          'vaultPrivateKeys',
        ].fold<int>(0, (sum, key) => sum + (data[key]! as List).length);
    if (count < 1 || count > 100) {
      throw const FormatException('Rotation batch exceeds item limit');
    }
    await _dio.put<Map<String, dynamic>>(
      '/api/vaults/$vaultId/key-rotations/$rotationId/batch',
      data: data,
      cancelToken: cancelToken,
    );
  }

  Future<RotationCommitResult> commit(
    String vaultId,
    String rotationId,
    String fencingToken,
    CancelToken cancelToken,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/key-rotations/$rotationId/commit',
      data: {
        'vaultId': vaultId,
        'rotationId': rotationId,
        'fencingToken': fencingToken,
      },
      options: Options(
        validateStatus: (status) => status == 200 || status == 409,
      ),
      cancelToken: cancelToken,
    );
    return RotationCommitResult(committed: response.statusCode == 200);
  }

  Future<RotationPage<T>> _sourcePage<T>(
    String path,
    String? fencingToken,
    String? afterId,
    int? afterVersion,
    CancelToken cancelToken,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: {
        'fencingToken': ?fencingToken,
        'pageSize': 100,
        'afterId': ?afterId,
        'afterVersion': ?afterVersion,
      },
      cancelToken: cancelToken,
    );
    final body = _body(response);
    final rawItems = body['items'];
    if (rawItems is! List || rawItems.length > 100) {
      throw const FormatException('Rotation source page exceeds limit');
    }
    return RotationPage(
      items: rawItems
          .map((item) => parse(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      nextAfterId: body['nextAfterId'] as String?,
      nextAfterVersion: body['nextAfterVersion'] as int?,
    );
  }

  Map<String, dynamic> _body(Response<Map<String, dynamic>> response) {
    final data = response.data;
    if (data == null) throw const FormatException('Empty rotation response');
    return data;
  }
}
