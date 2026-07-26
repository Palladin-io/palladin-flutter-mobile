import 'package:dio/dio.dart';

import '../models/create_vault_request.dart';
import '../models/encrypted_vault_summary_model.dart';
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

  Future<Map<String, dynamic>> issueVaultCreationChallenge() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/creation-challenges',
    );
    return response.data ?? (throw StateError('Empty Vault challenge'));
  }

  Future<Map<String, dynamic>> createEncryptedVault(
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults',
      data: payload,
    );
    return response.data ?? (throw StateError('Empty Vault response'));
  }

  /// Fetches only the encrypted Member key context needed by local sync.
  Future<Map<String, dynamic>> getMemberVaultKeyContext(String vaultId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId',
    );
    final data = response.data;
    if (data == null ||
        data['memberVaultKey'] is! Map ||
        data['memberKeyGeneration'] is! int) {
      throw const FormatException('Malformed encrypted Vault key context');
    }
    return {
      'memberVaultKey': Map<String, dynamic>.from(
        data['memberVaultKey'] as Map,
      ),
      'memberKeyGeneration': data['memberKeyGeneration'] as int,
    };
  }

  /// Fetches the complete encrypted Vault v2 projection for local settings.
  Future<Map<String, dynamic>> getEncryptedVault(String vaultId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId',
    );
    return response.data ?? (throw const FormatException('Empty Vault'));
  }

  /// Replaces only the authenticated encrypted Member metadata envelope.
  Future<Response<void>> replaceEncryptedMetadata(
    String vaultId,
    Map<String, dynamic> envelope,
  ) => _dio.put<void>(
    '/api/vaults/$vaultId',
    data: {'memberVaultMetadata': envelope},
    options: Options(
      validateStatus: (status) =>
          status == 204 || status == 400 || status == 409,
    ),
  );

  Future<void> uploadEncryptedAsset(
    String vaultId,
    Map<String, dynamic> payload,
  ) => _dio.post<void>('/api/vaults/$vaultId/assets', data: payload);

  Future<void> deleteEncryptedAsset(String vaultId, String assetId) =>
      _dio.delete<void>('/api/vaults/$vaultId/assets/$assetId');

  /// Fetches one bounded page of opaque Vault v2 projections.
  Future<EncryptedVaultPage> listEncryptedVaults({
    required int offset,
    int limit = 200,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults',
      queryParameters: {'offset': offset, 'limit': limit},
    );
    final data = response.data;
    if (data == null || data['vaults'] is! List || data['total'] is! int) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Malformed encrypted Vault list',
      );
    }
    return EncryptedVaultPage(
      vaults: (data['vaults'] as List)
          .map(
            (value) => EncryptedVaultSummaryModel.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
      total: data['total'] as int,
    );
  }

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
