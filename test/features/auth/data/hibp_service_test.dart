import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/data/services/hibp_service.dart';

/// Fake adapter that captures the requested path and returns a canned
/// `SUFFIX:COUNT` body — so the k-anonymity behaviour is tested without
/// ever hitting the network. The full password / hash never appears in
/// the request the adapter sees.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.statusCode = 200});

  final String body;
  final int statusCode;
  String? capturedPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedPath = options.path;
    return ResponseBody.fromString(body, statusCode);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const password = 'password123';
  final digest = sha1.convert(utf8.encode(password)).toString().toUpperCase();
  final prefix = digest.substring(0, 5);
  final suffix = digest.substring(5);

  Dio dioWith(_FakeAdapter adapter) {
    final dio = Dio(BaseOptions(responseType: ResponseType.plain));
    dio.httpClientAdapter = adapter;
    return dio;
  }

  test('only the 5-char SHA-1 prefix is sent to the range API', () async {
    final adapter = _FakeAdapter('$suffix:42\n');
    await HibpService(dio: dioWith(adapter)).check(password);
    expect(adapter.capturedPath, '/range/$prefix');
    // The request path must never carry the full digest or the password.
    expect(adapter.capturedPath, isNot(contains(suffix)));
    expect(adapter.capturedPath, isNot(contains(password)));
  });

  test('reports pwned when the suffix is present with a non-zero count',
      () async {
    final adapter = _FakeAdapter('AAAA:1\r\n$suffix:99\r\nBBBB:3\r\n');
    final result = await HibpService(dio: dioWith(adapter)).check(password);
    expect(result, HibpResult.pwned);
  });

  test('reports notFound when the suffix is absent', () async {
    final adapter = _FakeAdapter('AAAA:1\nBBBB:3\n');
    final result = await HibpService(dio: dioWith(adapter)).check(password);
    expect(result, HibpResult.notFound);
  });

  test('a padded zero-count row is treated as not present', () async {
    final adapter = _FakeAdapter('$suffix:0\n');
    final result = await HibpService(dio: dioWith(adapter)).check(password);
    expect(result, HibpResult.notFound);
  });

  test('a network error yields unknown, never an exception', () async {
    final adapter = _FakeAdapter('', statusCode: 500);
    final dio = dioWith(adapter);
    // A 500 makes Dio throw internally; the service must swallow it.
    final result = await HibpService(dio: dio).check(password);
    expect(result, HibpResult.unknown);
  });

  test('an empty password is never checked', () async {
    final adapter = _FakeAdapter('$suffix:1\n');
    final result = await HibpService(dio: dioWith(adapter)).check('');
    expect(result, HibpResult.unknown);
    expect(adapter.capturedPath, isNull);
  });
}
