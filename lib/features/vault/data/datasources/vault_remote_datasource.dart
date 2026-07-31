import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/encrypted_vault_summary_model.dart';

/// Remote data source for the canonical encrypted Vault endpoints.
///
/// DioExceptions surface raw so callers can classify transport semantics.
class VaultRemoteDatasource {
  VaultRemoteDatasource(this._dio, {Dio? opaqueAssetDio})
    : _opaqueAssetDio = opaqueAssetDio ?? Dio();

  final Dio _dio;
  // Deliberately interceptor-free: presigned object-store URLs must never
  // receive the API bearer token, analytics headers or request logging.
  final Dio _opaqueAssetDio;

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

  /// Fetches authenticated metadata for one opaque encrypted asset.
  Future<EncryptedPresentationAssetMetadata> getEncryptedAsset(
    String vaultId,
    String assetId,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/assets/$assetId',
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('Empty encrypted asset metadata');
    }
    return EncryptedPresentationAssetMetadata.fromJson(data);
  }

  /// Downloads opaque ciphertext without interpreting or logging it.
  Future<Uint8List> downloadEncryptedAsset(
    EncryptedPresentationAssetMetadata metadata,
  ) async {
    final uri = Uri.tryParse(metadata.downloadUrl);
    if (uri == null ||
        !uri.hasScheme ||
        !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('Invalid encrypted asset location');
    }
    final response = await _opaqueAssetDio.get<ResponseBody>(
      metadata.downloadUrl,
      options: Options(
        responseType: ResponseType.stream,
        receiveDataWhenStatusError: false,
      ),
    );
    final body = response.data;
    if (body == null) {
      throw const FormatException('Empty encrypted asset');
    }
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in body.stream) {
      received += chunk.length;
      if (received > metadata.ciphertextLength) {
        throw const FormatException('Encrypted asset exceeds declared size');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

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
}

/// Authenticated metadata describing an opaque encrypted asset.
final class EncryptedPresentationAssetMetadata {
  const EncryptedPresentationAssetMetadata({
    required this.assetId,
    required this.target,
    required this.entryId,
    required this.mediaType,
    required this.ciphertextLength,
    required this.ciphertextSha256,
    required this.downloadUrl,
  });

  factory EncryptedPresentationAssetMetadata.fromJson(
    Map<String, dynamic> json,
  ) => EncryptedPresentationAssetMetadata(
    assetId: json['assetId'] as String,
    target: switch (json['target']) {
      'vault' => 1,
      'entry' => 2,
      _ => throw const FormatException(
        'Invalid encrypted asset target contract',
      ),
    },
    entryId: json['entryId'] as String?,
    mediaType: json['mediaType'] as String,
    ciphertextLength: json['ciphertextLength'] as int,
    ciphertextSha256: json['ciphertextSha256'] as String,
    downloadUrl: json['downloadUrl'] as String,
  );

  final String assetId;
  final int target;
  final String? entryId;
  final String mediaType;
  final int ciphertextLength;
  final String ciphertextSha256;
  final String downloadUrl;
}
