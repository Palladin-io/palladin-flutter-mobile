import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/network/auth_interceptor.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';

class _MockTokenStorage extends Mock implements SecureTokenStorage {}

/// Minimal [HttpClientAdapter] that returns a status per request and
/// counts how many times it was hit — enough to prove the interceptor does
/// (or does not) re-issue a request.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.statusFor);

  final int Function(RequestOptions options) statusFor;
  int callCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    return ResponseBody.fromString('{}', statusFor(options),
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
  }
}

void main() {
  late _MockTokenStorage storage;

  setUp(() {
    storage = _MockTokenStorage();
    when(() => storage.accessToken).thenAnswer((_) async => 'stale');
    when(() => storage.clearAll()).thenAnswer((_) async {});
  });

  Dio buildDio(_FakeAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(AuthInterceptor(tokenStorage: storage, dio: dio));
    return dio;
  }

  for (final retry in [false, true]) {
    test(
      'session guard blocks transport after asynchronous token lookup (retry: $retry)',
      () async {
        final token = Completer<String?>();
        when(() => storage.accessToken).thenAnswer((_) => token.future);
        final adapter = _FakeAdapter((_) => 200);
        final dio = buildDio(adapter);
        var current = true;
        final options = RequestOptions(
          path: '/api/vaults/vault/entries/entry/delete',
          method: 'POST',
          extra: {
            AuthInterceptor.sessionGuardKey: () => current,
            '__retried__': retry,
          },
        );
        final operation = dio.fetch<dynamic>(options);
        final expectation = expectLater(
          operation,
          throwsA(
            isA<DioException>().having(
              (error) => error.type,
              'type',
              DioExceptionType.cancel,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        current = false;
        token.complete('token');
        await expectation;
        expect(adapter.callCount, 0);
        verifyNever(() => storage.clearAll());
      },
    );
  }

  test(
      'a 401 on /api/auth/refresh does NOT trigger another refresh and '
      'propagates the error', () async {
    final adapter = _FakeAdapter((_) => 401);
    final dio = buildDio(adapter);

    await expectLater(
      dio.post<dynamic>('/api/auth/refresh', data: {'refreshToken': 'x'}),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 401)),
    );

    // Only the original refresh request was sent — the interceptor did not
    // re-enter its own 401→refresh flow.
    expect(adapter.callCount, 1);
    verifyNever(() => storage.refreshToken);
    // The dead session was dropped.
    verify(() => storage.clearAll()).called(1);
  });

  test('a 401 on a normal request with no refresh token clears and propagates',
      () async {
    when(() => storage.refreshToken).thenAnswer((_) async => null);
    final adapter = _FakeAdapter((_) => 401);
    final dio = buildDio(adapter);

    await expectLater(
      dio.get<dynamic>('/api/account'),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 401)),
    );

    // No retry — the request was issued exactly once.
    expect(adapter.callCount, 1);
    verify(() => storage.clearAll()).called(1);
  });
}
