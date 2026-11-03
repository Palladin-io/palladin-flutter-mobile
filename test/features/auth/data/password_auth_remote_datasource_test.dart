import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/domain/password_auth_exceptions.dart';

class _RateLimitedAdapter implements HttpClientAdapter {
  _RateLimitedAdapter([this.retryAfter = '45']);

  final String retryAfter;

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
      'retry-after': [retryAfter],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status, [this.body = '{}']);

  final int status;
  final String body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

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

  for (final retryAfter in ['not-an-http-date', '0']) {
    test('malformed Retry-After "$retryAfter" remains a typed 429', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
      dio.httpClientAdapter = _RateLimitedAdapter(retryAfter);
      final malformedDatasource = PasswordAuthRemoteDatasource(dio);

      await expectLater(
        malformedDatasource.loginTotp(
          challengeToken: 'challenge',
          code: '123456',
        ),
        throwsA(
          isA<LoginRateLimitedException>().having(
            (error) => error.retryAfterSeconds,
            'retryAfterSeconds',
            isNull,
          ),
        ),
      );
    });
  }

  group('TOTP lifecycle sends the current auth credential', () {
    final credential = Uint8List.fromList(List.filled(32, 0xfb));
    final encoded = base64Url.encode(credential).replaceAll('=', '');

    (PasswordAuthRemoteDatasource, _StatusAdapter) build(
      int status, [
      String body = '{}',
    ]) {
      final adapter = _StatusAdapter(status, body);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..httpClientAdapter = adapter;
      return (PasswordAuthRemoteDatasource(dio), adapter);
    }

    test(
      'enroll and confirm carry the unpadded base64url credential',
      () async {
        final (enrollSource, enrollAdapter) = build(
          200,
          '{"secret":"JBSWY3DPEHPK3PXP","otpauthUri":"otpauth://totp/x"}',
        );
        await enrollSource.totpEnroll(credential);
        expect(enrollAdapter.requests.single.data, {
          'currentAuthCredential': encoded,
        });

        final (confirmSource, confirmAdapter) = build(
          200,
          '{"recoveryCodes":["a"]}',
        );
        expect(await confirmSource.totpConfirm('123456', credential), ['a']);
        expect(confirmAdapter.requests.single.data, {
          'code': '123456',
          'currentAuthCredential': encoded,
        });
      },
    );

    for (final (status, matcher) in [
      (403, isA<TotpCurrentCredentialException>()),
      (404, isA<TotpUnavailableException>()),
    ]) {
      test('$status maps to a typed credential error', () async {
        final (source, _) = build(status);
        await expectLater(source.totpEnroll(credential), throwsA(matcher));
        await expectLater(
          source.totpConfirm('123456', credential),
          throwsA(matcher),
        );
      });
    }

    test('confirm keeps 400 as a wrong code', () async {
      final (source, _) = build(400);
      await expectLater(
        source.totpConfirm('123456', credential),
        throwsA(isA<TotpInvalidException>()),
      );
    });
  });
}
