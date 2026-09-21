import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../config/env_config.dart';
import '../../domain/entities/entry_share.dart';
import '../../domain/entities/entry_share_reception.dart';
import 'entry_share_http_client.dart';

class EntryShareRecipientDatasource {
  EntryShareRecipientDatasource(EnvConfig config)
    : _http = EntryShareHttpClient(config);

  // Guest requests must never inherit auth, refresh, logging or analytics hooks.
  final EntryShareHttpClient _http;
  static const _metadataLimit = 16 * 1024;
  static const _deliveryLimit = 512 * 1024;

  String _path(String shareId, [EntryShareRecipientSession? session]) =>
      '/api/entry-shares/${Uri.encodeComponent(shareId)}/sessions'
      '${session == null ? '' : '/${Uri.encodeComponent(session.sessionId)}'}';

  Future<EntryShareRecipientSession> open(
    String shareId,
    String accessToken, {
    required CancelToken cancelToken,
  }) async {
    try {
      final body = await _post(_path(shareId), {
        'accessToken': accessToken,
      }, cancelToken);
      final data = jsonDecode(body) as Map<String, dynamic>;
      return EntryShareRecipientSession(
        sessionId: data['sessionId'] as String,
        sessionToken: data['sessionToken'] as String,
        expiresAt: data['expiresAt'] as String,
        recipientMode: data['recipientMode'] as String,
        protection: data['protection'] as String,
        shareExpiresAt: data['shareExpiresAt'] as String?,
        maximumReceipts: data['maximumReceipts'] as int?,
        otpRetryAfterSeconds: data['otpRetryAfterSeconds'] as int? ?? 0,
      );
    } catch (_) {
      throw const EntryShareRecipientRequestException();
    }
  }

  Future<Duration> requestOtp(
    String shareId,
    EntryShareRecipientSession session, {
    required int generation,
    required String language,
    required CancelToken cancelToken,
  }) async {
    try {
      final body = await _post('${_path(shareId, session)}/otp', {
        'sessionToken': session.sessionToken,
        'generation': generation,
        'language': language,
      }, cancelToken);
      final data = jsonDecode(body) as Map<String, dynamic>;
      return Duration(seconds: data['retryAfterSeconds'] as int);
    } catch (_) {
      throw const EntryShareRecipientRequestException();
    }
  }

  Future<void> verifyOtp(
    String shareId,
    EntryShareRecipientSession session, {
    required int generation,
    required String code,
    required CancelToken cancelToken,
  }) async => _post('${_path(shareId, session)}/verify-otp', {
    'sessionToken': session.sessionToken,
    'generation': generation,
    'code': code,
  }, cancelToken);

  Future<void> verifySecret(
    String shareId,
    EntryShareRecipientSession session, {
    required String secret,
    required CancelToken cancelToken,
  }) async => _post('${_path(shareId, session)}/verify-secret', {
    'sessionToken': session.sessionToken,
    'secret': secret,
  }, cancelToken);

  Future<EntryShareDelivery> receive(
    String shareId,
    EntryShareRecipientSession session, {
    required CancelToken cancelToken,
  }) async {
    try {
      final body = await _post(
        '${_path(shareId, session)}/delivery',
        {'sessionToken': session.sessionToken},
        cancelToken,
        maximumBytes: _deliveryLimit,
      );
      final data = jsonDecode(body) as Map<String, dynamic>;
      return EntryShareDelivery(
        authority: EntryShareScope(
          shareId: data['shareId'] as String,
          organizationId: data['organizationId'] as String,
          vaultId: data['vaultId'] as String,
          entryId: data['entryId'] as String,
          sourceRevision: data['sourceRevision'] as String,
          expiresAt: data['expiresAt'] as String,
        ),
        packet: EntryShareCiphertext(
          nonce: data['nonce'] as String,
          ciphertext: data['ciphertext'] as String,
        ),
      );
    } catch (_) {
      throw const EntryShareRecipientRequestException();
    }
  }

  Future<void> confirmDisplay(
    String shareId,
    EntryShareRecipientSession session, {
    required CancelToken cancelToken,
  }) async => _post('${_path(shareId, session)}/confirmation', {
    'sessionToken': session.sessionToken,
  }, cancelToken);

  Future<void> end(
    String shareId,
    EntryShareRecipientSession session, {
    required CancelToken cancelToken,
  }) async => _post('${_path(shareId, session)}/end', {
    'sessionToken': session.sessionToken,
  }, cancelToken);

  Future<String> _post(
    String path,
    Map<String, Object> body,
    CancelToken cancelToken, {
    int maximumBytes = _metadataLimit,
  }) async {
    try {
      return await _http.request(
        method: 'POST',
        path: path,
        encodedBody: jsonEncode(body),
        cancelToken: cancelToken,
        maximumBytes: maximumBytes,
      );
    } catch (_) {
      throw const EntryShareRecipientRequestException();
    }
  }

  void close() => _http.close();
}
