import 'package:dio/dio.dart';

import '../models/create_vault_request.dart';
import '../models/vault_model.dart';

/// Remote data source for vault CRUD endpoints.
///
/// Communicates with the .NET backend Vault module at `/api/vaults`.
/// Returns DTOs (`VaultModel`) — domain mapping happens in the
/// repository layer. DioExceptions surface raw so the repository can
/// classify error semantics (404, 403/plan-limit, 403/full-mode-not-
/// allowed, etc.) and translate them into typed `VaultException`s.
class VaultRemoteDatasource {
  VaultRemoteDatasource(this._dio);

  final Dio _dio;

  /// `GET /api/vaults` → list of vaults visible to the current user.
  Future<List<VaultModel>> listVaults() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/vaults');
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
    }
    final raw = (data['vaults'] as List<dynamic>? ?? const <dynamic>[]);
    return raw
        .map((e) => VaultModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// `GET /api/vaults/{id}` → a single vault.
  Future<VaultModel> getVault(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/vaults/$id');
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
    }
    return VaultModel.fromJson(data);
  }

  /// `POST /api/vaults` → 201 Created with the created vault payload.
  Future<VaultModel> createVault(CreateVaultRequest request) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults',
      data: request.toJson(),
    );
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
    }
    return VaultModel.fromJson(data);
  }

  /// `PUT /api/vaults/{id}` → 204 No Content (patch semantics).
  Future<void> updateVault(String id, UpdateVaultRequest request) async {
    await _dio.put<void>(
      '/api/vaults/$id',
      data: request.toJson(),
    );
  }

  /// `DELETE /api/vaults/{id}` → 204 No Content.
  Future<void> deleteVault(String id) async {
    await _dio.delete<void>('/api/vaults/$id');
  }

  /// `POST /api/vaults/{id}/icon/presign` → presigned S3 upload URL.
  Future<PresignResponse> presignVaultIcon(String vaultId, String extension) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/icon/presign',
      data: {'vaultId': vaultId, 'extension': extension},
    );
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
    }
    return PresignResponse(
      uploadUrl: data['uploadUrl'] as String,
      publicUrl: data['publicUrl'] as String,
    );
  }
}

class PresignResponse {
  const PresignResponse({required this.uploadUrl, required this.publicUrl});
  final String uploadUrl;
  final String publicUrl;
}
