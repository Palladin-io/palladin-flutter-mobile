import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../../../config/env_config.dart';
import '../../../../core/network/certificate_pinning.dart';
import '../../domain/entities/entry_share.dart';
import '../../domain/entities/entry_share_reception.dart';

class EntryShareRecipientDatasource {
  EntryShareRecipientDatasource(EnvConfig config)
    : _dio = Dio(
        BaseOptions(
          baseUrl: config.apiBaseUrl,
          connectTimeout: _timeout,
          sendTimeout: _timeout,
          receiveTimeout: _timeout,
          followRedirects: false,
          maxRedirects: 0,
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
          headers: {
            'Accept': Headers.jsonContentType,
            'Content-Type': Headers.jsonContentType,
            'Cache-Control': 'no-store',
          },
        ),
      ) {
    final pinning = CertificatePinningService(config.certificatePins);
    _dio.httpClientAdapter = IOHttpClientAdapter(
      validateCertificate: pinning.isEnabled
          ? (cert, host, port) => pinning.validateLeaf(cert, host)
          : null,
    );
  }

  // Guest requests must never inherit auth, refresh, logging or analytics hooks.
  final Dio _dio;
  static const _timeout = Duration(seconds: 15);
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
      );
    } catch (_) {
      throw const EntryShareRecipientRequestException();
    }
  }

  Future<void> requestOtp(
    String shareId,
    EntryShareRecipientSession session, {
    required int generation,
    required String language,
    required CancelToken cancelToken,
  }) async => _post('${_path(shareId, session)}/otp', {
    'sessionToken': session.sessionToken,
    'generation': generation,
    'language': language,
  }, cancelToken);

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
    StreamIterator<Uint8List>? stream;
    final bytes = BytesBuilder(copy: false);
    Uint8List? decoded;
    try {
      _checkCancellation(cancelToken);
      final response = await _dio.post<ResponseBody>(
        path,
        data: body,
        cancelToken: cancelToken,
      );
      stream = StreamIterator(response.data!.stream.timeout(_timeout));
      final status = response.statusCode!;
      if (status < 200 || status >= 300) {
        throw const EntryShareRecipientRequestException();
      }
      while (await stream.moveNext()) {
        _checkCancellation(cancelToken);
        final chunk = stream.current;
        if (bytes.length + chunk.length > maximumBytes) {
          throw const EntryShareRecipientRequestException();
        }
        bytes.add(chunk);
      }
      _checkCancellation(cancelToken);
      decoded = bytes.takeBytes();
      return utf8.decode(decoded);
    } catch (_) {
      throw const EntryShareRecipientRequestException();
    } finally {
      try {
        await stream?.cancel();
      } catch (_) {
        throw const EntryShareRecipientRequestException();
      } finally {
        final remaining = bytes.takeBytes();
        remaining.fillRange(0, remaining.length, 0);
        decoded?.fillRange(0, decoded.length, 0);
      }
    }
  }

  void _checkCancellation(CancelToken token) {
    if (token.isCancelled) throw const EntryShareRecipientRequestException();
  }

  void close() => _dio.close(force: true);
}
