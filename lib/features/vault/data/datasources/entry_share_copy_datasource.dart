import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../config/env_config.dart';
import '../../../../core/crypto/vault_session_store.dart';
import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/jwt_claims.dart';
import '../../domain/entities/entry_share_copy.dart';
import '../../domain/entities/entry_share_list.dart';
import 'entry_share_http_client.dart';

class EntryShareCopyDatasource {
  EntryShareCopyDatasource(EnvConfig config, this._tokens, this._keys)
    : _http = EntryShareHttpClient(config);

  final SecureTokenStorage _tokens;
  final VaultSessionStore _keys;
  final EntryShareHttpClient _http;

  String _vaultPath(String vaultId) =>
      '/api/vaults/${Uri.encodeComponent(vaultId)}';

  Future<Map<String, dynamic>> vaults(
    int offset,
    EntrySharingSession owner,
    CancelToken cancelToken,
  ) async {
    try {
      final body = await _request(
        'GET',
        '/api/vaults?limit=50&offset=$offset',
        owner,
        cancelToken,
        maximumBytes: 2 * 1024 * 1024,
      );
      return jsonDecode(body) as Map<String, dynamic>;
    } on EntryShareCopyException {
      rethrow;
    } catch (_) {
      throw const EntryShareCopyException(EntryShareCopyError.request);
    }
  }

  Future<Map<String, dynamic>> vault(
    String vaultId,
    EntrySharingSession owner,
    CancelToken cancelToken,
  ) async {
    try {
      final body = await _request(
        'GET',
        _vaultPath(vaultId),
        owner,
        cancelToken,
        maximumBytes: 256 * 1024,
      );
      return jsonDecode(body) as Map<String, dynamic>;
    } on EntryShareCopyException {
      rethrow;
    } catch (_) {
      throw const EntryShareCopyException(EntryShareCopyError.request);
    }
  }

  Future<String> challenge(
    String vaultId,
    EntrySharingSession owner,
    CancelToken cancelToken,
  ) async {
    try {
      final body = await _request(
        'POST',
        '${_vaultPath(vaultId)}/entries/creation-challenges',
        owner,
        cancelToken,
        encodedBody: '{"count":1}',
        maximumBytes: 4096,
      );
      final data = jsonDecode(body) as Map<String, dynamic>;
      return (data['items'] as List).single['entryId'] as String;
    } on EntryShareCopyException {
      rethrow;
    } catch (_) {
      throw const EntryShareCopyException(EntryShareCopyError.request);
    }
  }

  Future<void> create(
    String vaultId,
    String encodedBody,
    EntrySharingSession owner,
    CancelToken cancelToken,
  ) async => _request(
    'POST',
    '${_vaultPath(vaultId)}/entries',
    owner,
    cancelToken,
    encodedBody: encodedBody,
    maximumBytes: 16 * 1024,
  );

  Future<String> _request(
    String method,
    String path,
    EntrySharingSession owner,
    CancelToken cancelToken, {
    String? encodedBody,
    required int maximumBytes,
  }) async {
    try {
      if (cancelToken.isCancelled ||
          owner.keyGeneration != _keys.memberKeySessionGeneration) {
        throw const EntryShareCopyException(EntryShareCopyError.cancelled);
      }
      final token = await _tokens.accessToken;
      if (token == null ||
          cancelToken.isCancelled ||
          owner.keyGeneration != _keys.memberKeySessionGeneration) {
        throw const EntryShareCopyException(EntryShareCopyError.cancelled);
      }
      final claims = JwtClaims.decodePayload(token);
      final authorization = claims['authz_ver'];
      if (claims['sub'] != owner.principalId ||
          JwtClaims.organizationIdFrom(token) != owner.organizationId ||
          (authorization is! String && authorization is! int) ||
          '$authorization' != owner.authorizationGeneration) {
        throw const EntryShareCopyException(EntryShareCopyError.cancelled);
      }
      return await _http.request(
        method: method,
        path: path,
        cancelToken: cancelToken,
        encodedBody: encodedBody,
        accountToken: token,
        maximumBytes: maximumBytes,
      );
    } on EntryShareCopyException {
      rethrow;
    } catch (_) {
      throw const EntryShareCopyException(EntryShareCopyError.request);
    }
  }

  void close() => _http.close();
}
