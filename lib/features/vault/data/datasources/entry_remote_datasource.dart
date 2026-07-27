import 'package:dio/dio.dart';

import '../models/create_entry_request.dart';
import '../models/creation_challenge_model.dart';
import '../models/entry_model.dart';
import '../models/entry_v2_contracts.dart';
import '../models/import_entries_request.dart';
import '../models/update_entry_request.dart';
import 'vault_remote_datasource.dart' show PresignResponse;

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

  /// Returns opaque protocol-v2 list rows; projection decryption belongs to
  /// the repository and never to transport code.
  Future<List<Map<String, dynamic>>> listEntriesV2(String vaultId) async {
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
    return (data['items'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  /// Returns the opaque protocol-v2 detail bundle.
  Future<Map<String, dynamic>> getEntryV2(
    String vaultId,
    String entryId,
  ) async {
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
    return data;
  }

  /// Exhausts the active-grant cursor for atomic Entry refresh operations.
  Future<List<Map<String, dynamic>>> listActiveGrants(String vaultId) async {
    final grants = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/vaults/$vaultId/grants',
        queryParameters: {
          'status': 'active',
          'pageSize': 100,
          'cursor': ?cursor,
        },
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
      grants.addAll(
        (data['items'] as List<dynamic>? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      cursor = data['nextCursor'] as String?;
    } while (cursor != null && cursor.isNotEmpty);
    return grants;
  }

  /// Persists one complete protocol-v2 Entry transition atomically.
  Future<Map<String, dynamic>> createEntryV2(
    String vaultId,
    CreateEntryV2Request request,
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
    return data;
  }

  /// Commits a complete optimistic protocol-v2 Entry revision.
  Future<Map<String, dynamic>> updateEntryV2(
    String vaultId,
    String entryId,
    UpdateEntryV2Request request,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries/$entryId',
      data: request.toJson(),
    );
    return response.data ?? const <String, dynamic>{};
  }

  /// Reserves opaque Entry IDs before their scoped envelope descriptors are
  /// constructed. No plaintext Entry data is sent in this request.
  Future<List<EntryCreationChallengeModel>> issueCreationChallenges(
    String vaultId, {
    int count = 1,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries/creation-challenges',
      data: {'vaultId': vaultId, 'count': count},
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
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .map(
          (item) => EntryCreationChallengeModel.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

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
    // Backend response envelope: { "items": [...], "nextCursor": "..." }
    // The list item shape (EntryListItem) omits vaultId — inject from URL.
    final raw = (data['items'] as List<dynamic>? ?? const <dynamic>[]);
    return raw
        .map(
          (e) => EntryModel.fromJson(
            e as Map<String, dynamic>,
            contextVaultId: vaultId,
          ),
        )
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

  /// `POST /api/vaults/{vaultId}/entries` → 201 Created.
  ///
  /// The backend returns only `{"id": "..."}`. The full [EntryModel] is
  /// built locally from [request] + the returned ID so downstream code
  /// never has to re-fetch after create.
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
    final id = data['id'] as String;
    final now = DateTime.now().toUtc().toIso8601String();
    return EntryModel(
      id: id,
      vaultId: vaultId,
      label: request.label,
      description: request.description,
      icon: request.icon,
      type: request.type,
      urlDomain: request.urlDomain,
      createdAt: now,
      updatedAt: now,
      accessCount: 0,
    );
  }

  /// `DELETE /api/vaults/{vaultId}/entries/{entryId}` → 204 No Content.
  Future<void> deleteEntry(String vaultId, String entryId) async {
    await _dio.delete<void>('/api/vaults/$vaultId/entries/$entryId');
  }

  /// `POST /api/vaults/{vaultId}/entries/import` → `{ importedCount,
  /// entryIds }`. Bulk-creates pre-encrypted entries. The caller chunks
  /// the request to the backend's per-call limit (500).
  Future<int> importEntries(
    String vaultId,
    ImportEntriesRequest request,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries/import',
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
    return (data['importedCount'] as int?) ?? request.entries.length;
  }

  /// Bulk-creates canonical protocol-v2 Entry bundles.
  Future<int> importEntriesV2(
    String vaultId, {
    required String format,
    required List<Map<String, Object?>> entries,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries/import',
      data: {'format': format, 'entries': entries},
    );
    return (response.data?['importedCount'] as int?) ?? entries.length;
  }

  /// `POST /api/vaults/{vaultId}/export-audit` → records that a plaintext
  /// export happened. Fire-and-forget from the caller's perspective — an
  /// audit failure must not block the export UX.
  Future<void> logExportAudit(
    String vaultId,
    String format,
    int entryCount,
  ) async {
    await _dio.post<void>(
      '/api/vaults/$vaultId/export-audit',
      data: {'format': format, 'entryCount': entryCount},
    );
  }

  /// `PUT /api/vaults/{vaultId}/entries/{entryId}` → 204 No Content.
  ///
  /// Updates label, description, icon, type, content (re-encrypted),
  /// and urlDomain. Patch semantics: omitted optional fields are not changed.
  Future<void> updateEntry(
    String vaultId,
    String entryId,
    UpdateEntryRequest request,
  ) async {
    await _dio.put<void>(
      '/api/vaults/$vaultId/entries/$entryId',
      data: request.toJson(),
    );
  }

  /// `POST /api/vaults/{vaultId}/entries/{entryId}/icon/presign` →
  /// presigned S3 upload URL for an entry icon.
  Future<PresignResponse> presignEntryIcon(
    String vaultId,
    String entryId,
    String extension,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries/$entryId/icon/presign',
      data: {'vaultId': vaultId, 'entryId': entryId, 'extension': extension},
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

  /// `PUT /api/vaults/{vaultId}/entries/{entryId}` — updates only the
  /// icon field (patch semantics on the backend).
  Future<void> updateEntryIcon(
    String vaultId,
    String entryId,
    String iconUrl,
  ) async {
    await _dio.put<void>(
      '/api/vaults/$vaultId/entries/$entryId',
      data: {'vaultId': vaultId, 'entryId': entryId, 'icon': iconUrl},
    );
  }
}
