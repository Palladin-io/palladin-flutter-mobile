import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/domain/password_auth_exceptions.dart';

class _RateLimitedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{}',
    429,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
      'retry-after': ['45'],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  late PasswordAuthRemoteDatasource datasource;

  setUp(() {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
    dio.httpClientAdapter = _RateLimitedAdapter();
    datasource = PasswordAuthRemoteDatasource(dio);
  });

  test('login maps 429 and Retry-After to a typed rate-limit error', () async {
    await expectLater(
      datasource.login(email: 'member@example.com', authCredential: 'hash'),
      throwsA(
        isA<LoginRateLimitedException>().having(
          (error) => error.retryAfterSeconds,
          'retryAfterSeconds',
          45,
        ),
      ),
    );
  });

  test(
    'TOTP login maps 429 and Retry-After to a typed rate-limit error',
    () async {
      await expectLater(
        datasource.loginTotp(challengeToken: 'challenge', code: '123456'),
        throwsA(
          isA<LoginRateLimitedException>().having(
            (error) => error.retryAfterSeconds,
            'retryAfterSeconds',
            45,
          ),
        ),
      );
    },
  );

  test('KDF bootstrap maps middleware 429 to the same typed error', () async {
    await expectLater(
      datasource.fetchLoginKdf(
        'member@example.com',
        profileId: 'identity-argon2id-password-v1',
      ),
      throwsA(isA<LoginRateLimitedException>()),
    );
  });
}
