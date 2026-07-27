import 'package:dio/dio.dart';

import '../models/creation_challenge_model.dart';
import '../models/create_vault_request.dart' show UpdateVaultRequest;
import '../models/vault_v2_contracts.dart';

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

  /// Reserves the opaque Vault ID that must be authenticated by every
  /// envelope in the subsequent atomic create request.
  Future<VaultCreationChallengeModel> issueCreationChallenge() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/creation-challenges',
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
    return VaultCreationChallengeModel.fromJson(data);
  }

  /// `GET /api/vaults` → list of vaults visible to the current user.
  Future<List<Map<String, dynamic>>> listVaults() async {
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
    return raw.map((e) => e as Map<String, dynamic>).toList(growable: false);
  }

  /// `GET /api/vaults/{id}` → a single vault.
  Future<Map<String, dynamic>> getVault(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/api/vaults/$id');
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
    }
    return data;
  }

  /// `POST /api/vaults` → 201 Created with the created vault payload.
  Future<Map<String, dynamic>> createVault(CreateVaultV2Request request) async {
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
    return data;
  }

  /// `PUT /api/vaults/{id}` → 204 No Content (patch semantics).
  Future<void> updateVault(String id, UpdateVaultRequest request) async {
    await _dio.put<void>('/api/vaults/$id', data: request.toJson());
  }

  /// `DELETE /api/vaults/{id}` → 204 No Content.
  Future<void> deleteVault(String id) async {
    await _dio.delete<void>('/api/vaults/$id');
  }

  /// `GET /api/vaults/{id}` → extracts the `wrappedVK` field for the
  /// current member from the vault detail response. The field is included
  /// in the single-vault endpoint but excluded from the list endpoint so
  /// it never leaks into summary responses.
  Future<String> getVaultWrappedKey(String vaultId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId',
    );
    final data = response.data;
    if (data == null || data['wrappedVK'] is! String) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty or malformed vault response — wrappedVK missing',
      );
    }
    return data['wrappedVK'] as String;
  }

  /// `POST /api/vaults/{id}/icon/presign` → presigned S3 upload URL.
  Future<PresignResponse> presignVaultIcon(
    String vaultId,
    String extension,
  ) async {
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
