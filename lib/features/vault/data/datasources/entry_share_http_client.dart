import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../../../config/env_config.dart';
import '../../../../core/network/certificate_pinning.dart';

final class EntryShareHttpException implements Exception {
  const EntryShareHttpException([this.statusCode]);
  final int? statusCode;
  @override
  String toString() => 'EntryShareHttpException';
}

/// Each flow owns its transport; account auth is supplied per request, never inherited.
final class EntryShareHttpClient {
  EntryShareHttpClient(EnvConfig config)
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

  static const _timeout = Duration(seconds: 15);
  final Dio _dio;

  Future<String> request({
    required String method,
    required String path,
    required CancelToken cancelToken,
    required int maximumBytes,
    String? encodedBody,
    String? accountToken,
  }) async {
    StreamIterator<Uint8List>? stream;
    final bytes = BytesBuilder(copy: false);
    Uint8List? decoded;
    try {
      _checkCancellation(cancelToken);
      final response = await _dio.request<ResponseBody>(
        path,
        data: encodedBody,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          headers: {
            if (accountToken != null) 'Authorization': 'Bearer $accountToken',
          },
        ),
      );
      stream = StreamIterator(response.data!.stream.timeout(_timeout));
      final status = response.statusCode!;
      if (status < 200 || status >= 300) {
        throw EntryShareHttpException(status);
      }
      while (await stream.moveNext()) {
        _checkCancellation(cancelToken);
        final chunk = stream.current;
        if (bytes.length + chunk.length > maximumBytes) {
          throw const EntryShareHttpException();
        }
        bytes.add(chunk);
      }
      _checkCancellation(cancelToken);
      decoded = bytes.takeBytes();
      return utf8.decode(decoded);
    } on EntryShareHttpException {
      rethrow;
    } catch (_) {
      throw const EntryShareHttpException();
    } finally {
      try {
        await stream?.cancel();
      } catch (_) {
        throw const EntryShareHttpException();
      } finally {
        final remaining = bytes.takeBytes();
        remaining.fillRange(0, remaining.length, 0);
        decoded?.fillRange(0, decoded.length, 0);
      }
    }
  }

  void _checkCancellation(CancelToken token) {
    if (token.isCancelled) throw const EntryShareHttpException();
  }

  void close() => _dio.close(force: true);
}
