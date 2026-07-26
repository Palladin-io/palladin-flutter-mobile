import 'package:dio/dio.dart';

import '../models/create_entry_request.dart';
import '../models/entry_model.dart';
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

  Future<Map<String, dynamic>> getCanonicalEntry(
    String vaultId,
    String entryId,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries/$entryId',
    );
    return response.data ??
        (throw const FormatException('Empty canonical Entry'));
  }

  Future<Response<Map<String, dynamic>>> updateCanonicalEntry(
    String vaultId,
    String entryId,
    Map<String, dynamic> payload,
  ) => _dio.put<Map<String, dynamic>>(
    '/api/vaults/$vaultId/entries/$entryId',
    data: payload,
    options: Options(
      validateStatus: (status) =>
          status == 200 || status == 400 || status == 409,
    ),
  );

  /// Restores an Archived Entry through one versioned lifecycle transition.
  ///
  /// The caller owns the encrypted projection payload. A transport retry must
  /// reuse the exact same payload so the backend can recognize it as an
  /// idempotent lifecycle retry.
  Future<Response<Map<String, dynamic>>> restoreCanonicalEntry(
    String vaultId,
    String entryId,
    Map<String, dynamic> payload,
  ) => _dio.post<Map<String, dynamic>>(
    '/api/vaults/$vaultId/entries/$entryId/restore',
    data: payload,
    options: Options(
      validateStatus: (status) =>
          status == 200 || status == 400 || status == 409,
    ),
  );

  Future<Map<String, dynamic>> listRecentlyDeleted(
    String vaultId, {
    String? cursor,
    int pageSize = 100,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries/recently-deleted',
      queryParameters: {'cursor': ?cursor, 'pageSize': pageSize},
    );
    return response.data ??
        (throw const FormatException('Empty Recently Deleted response'));
  }

  /// Permanently destroys an already Deleted Entry without secret material.
  Future<Response<void>> destroyEntry(String vaultId, String entryId) =>
      _dio.post<void>(
        '/api/vaults/$vaultId/entries/$entryId/destroy',
        options: Options(
          validateStatus: (status) =>
              status == 204 || status == 404 || status == 409,
        ),
      );

  /// Loads one bounded page of immutable encrypted Entry versions.
  Future<Map<String, dynamic>> getEntryHistory(
    String vaultId,
    String entryId, {
    String? beforeRevision,
    int pageSize = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries/$entryId/history',
      queryParameters: {
        'beforeRevision': ?beforeRevision,
        'pageSize': pageSize,
      },
    );
    return response.data ??
        (throw const FormatException('Empty Entry history response'));
  }

  Future<String> issueCreationChallenge(String vaultId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries/creation-challenges',
    );
    final items = response.data?['items'];
    if (items is! List || items.isEmpty || items.first is! Map) {
      throw const FormatException('Malformed Entry creation challenge');
    }
    final entryId = (items.first as Map)['entryId'];
    if (entryId is! String) throw const FormatException('Malformed entryId');
    return entryId;
  }

  Future<Map<String, dynamic>> createCanonicalEntry(
    String vaultId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/vaults/$vaultId/entries',
      data: payload,
    );
    return response.data ??
        (throw const FormatException('Empty canonical Entry response'));
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
