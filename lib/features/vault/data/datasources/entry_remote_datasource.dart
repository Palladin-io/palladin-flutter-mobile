import 'package:dio/dio.dart';

import '../models/create_entry_request.dart';
import '../models/entry_model.dart';

/// Remote data source for the per-vault entry endpoints.
///
/// All routes are nested under the parent vault — the backend uses the
/// `vaultId` segment for authorization (caller must be a vault member
/// or hold `VaultManage`). DTOs (`EntryModel` / `EntryDetailModel`) are
/// returned as-is and translated to domain entities at the repository
/// layer.
class EntryRemoteDatasource {
  EntryRemoteDatasource(this._dio);

  final Dio _dio;

  /// `GET /api/vaults/{vaultId}/entries` → list of entry summaries
  /// (no encrypted payload).
  Future<List<EntryModel>> listEntries(String vaultId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries',
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
    final raw = (data['entries'] as List<dynamic>? ?? const <dynamic>[]);
    return raw
        .map((e) => EntryModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// `GET /api/vaults/{vaultId}/entries/{entryId}` → entry detail
  /// including the encrypted payload (blob + nonce). Used on reveal.
  Future<EntryDetailModel> getEntry(String vaultId, String entryId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries/$entryId',
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
    return EntryDetailModel.fromJson(data);
  }

  /// `POST /api/vaults/{vaultId}/entries` → 201 Created with the entry
  /// summary payload (no blob — the caller already has the plaintext).
  Future<EntryModel> createEntry(
    String vaultId,
    CreateEntryRequest request,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries',
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
    return EntryModel.fromJson(data);
  }

  /// `DELETE /api/vaults/{vaultId}/entries/{entryId}` → 204 No Content.
  Future<void> deleteEntry(String vaultId, String entryId) async {
    await _dio.delete<void>('/api/vaults/$vaultId/entries/$entryId');
  }
}
