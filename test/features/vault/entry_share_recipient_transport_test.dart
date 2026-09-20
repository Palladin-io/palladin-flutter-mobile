import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_share_recipient_datasource.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_reception.dart';

class _Config extends Mock implements EnvConfig {}

const _shareId = '00112233-4455-4677-8899-aabbccddeeff';
const _session = EntryShareRecipientSession(
  sessionId: 'session/one',
  sessionToken: 'synthetic-session-bearer',
  expiresAt: '2026-09-22T12:00:00.123456789Z',
  recipientMode: 'namedRecipient',
  protection: 'pin',
);
final _sessionJson = {
  'sessionId': _session.sessionId,
  'sessionToken': _session.sessionToken,
  'expiresAt': _session.expiresAt,
  'recipientMode': _session.recipientMode,
  'protection': _session.protection,
};
final _failure = throwsA(
  isA<EntryShareRecipientRequestException>().having(
    (error) => error.toString(),
    'redacted error',
    'EntryShareRecipientRequestException',
  ),
);

void main() {
  late HttpServer server;
  late EntryShareRecipientDatasource api;
  late Future<void> Function(HttpRequest) handler;
  late List<({Uri uri, HttpHeaders headers, String body})> requests;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final config = _Config();
    when(() => config.apiBaseUrl).thenReturn('http://127.0.0.1:${server.port}');
    when(() => config.certificatePins).thenReturn([]);
    api = EntryShareRecipientDatasource(config);
    requests = [];
    handler = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(_sessionJson));
      await request.response.close();
    };
    server.listen((request) async {
      requests.add((
        uri: request.uri,
        headers: request.headers,
        body: await utf8.decoder.bind(request).join(),
      ));
      await handler(request);
    });
  });

  tearDown(() async {
    api.close();
    await server.close(force: true);
  });

  test('uses actual guest HTTP with no auth, cookies or analytics', () async {
    final session = await api.open(
      _shareId,
      'synthetic-access',
      cancelToken: CancelToken(),
    );
    expect(session.sessionId, _session.sessionId);
    expect(session.expiresAt, _session.expiresAt);
    final request = requests.single;
    expect(request.uri.toString(), '/api/entry-shares/$_shareId/sessions');
    expect(jsonDecode(request.body), {'accessToken': 'synthetic-access'});
    expect(request.headers.value('authorization'), isNull);
    expect(request.headers.value('cookie'), isNull);
    expect(request.headers.value('referer'), isNull);
    expect(request.headers.value('cache-control'), 'no-store');
    expect(request.headers.value('x-posthog-session-id'), isNull);
    expect(request.headers.value('x-posthog-distinct-id'), isNull);
  });

  test('does not accept a Set-Cookie into subsequent requests', () async {
    handler = (request) async {
      request.response.headers.add('set-cookie', 'guest=synthetic; Path=/');
      request.response.write(jsonEncode(_sessionJson));
      await request.response.close();
    };
    await api.open(_shareId, 'synthetic-access', cancelToken: CancelToken());
    await api.open(_shareId, 'synthetic-access', cancelToken: CancelToken());
    expect(requests.length, 2);
    expect(requests.last.headers.value('cookie'), isNull);
  });

  for (final status in [301, 302, 303, 307, 308, 401, 429, 500]) {
    test(
      'HTTP $status is redacted without redirect, refresh or retry',
      () async {
        handler = (request) async {
          request.response.statusCode = status;
          request.response.headers.set('location', '/unexpected');
          request.response.write('synthetic secret-bearing error');
          await request.response.close();
        };
        await expectLater(
          api.open(_shareId, 'synthetic-access', cancelToken: CancelToken()),
          _failure,
        );
        expect(requests.length, 1);
      },
    );
  }

  test(
    'all proof/delivery/confirmation/end methods use exact body contracts',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/crypto/entry-share-v1.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      handler = (request) async {
        if (request.uri.path.endsWith('/delivery')) {
          request.response.write(
            jsonEncode({
              ...fixture['scope'] as Map<String, dynamic>,
              'nonce': fixture['nonce'],
              'ciphertext': fixture['ciphertext'],
              'additiveField': true,
            }),
          );
        } else {
          request.response.statusCode = 204;
        }
        await request.response.close();
      };
      final cancel = CancelToken();
      await api.requestOtp(
        _shareId,
        _session,
        generation: 2,
        language: 'pl',
        cancelToken: cancel,
      );
      await api.verifyOtp(
        _shareId,
        _session,
        generation: 2,
        code: '012345',
        cancelToken: cancel,
      );
      await api.verifySecret(
        _shareId,
        _session,
        secret: ' exact secret ',
        cancelToken: cancel,
      );
      final delivery = await api.receive(
        _shareId,
        _session,
        cancelToken: cancel,
      );
      await api.confirmDisplay(_shareId, _session, cancelToken: cancel);
      await api.end(_shareId, _session, cancelToken: cancel);
      expect(
        delivery.authority.sourceRevision,
        fixture['scope']['sourceRevision'],
      );
      expect(delivery.authority.expiresAt, fixture['scope']['expiresAt']);
      expect(delivery.packet.ciphertext, fixture['ciphertext']);
      expect(requests.map((r) => r.uri.toString()), [
        for (final suffix in [
          'otp',
          'verify-otp',
          'verify-secret',
          'delivery',
          'confirmation',
          'end',
        ])
          '/api/entry-shares/$_shareId/sessions/session%2Fone/$suffix',
      ]);
      expect(requests.map((r) => jsonDecode(r.body)), [
        {
          'sessionToken': _session.sessionToken,
          'generation': 2,
          'language': 'pl',
        },
        {
          'sessionToken': _session.sessionToken,
          'generation': 2,
          'code': '012345',
        },
        {'sessionToken': _session.sessionToken, 'secret': ' exact secret '},
        for (var i = 0; i < 3; i++) {'sessionToken': _session.sessionToken},
      ]);
      for (final request in requests) {
        expect(request.uri.hasQuery, false);
        expect(request.uri.hasFragment, false);
        expect(request.body, isNot(contains('key')));
        expect(request.headers.value('authorization'), isNull);
      }
    },
  );

  test(
    'additive metadata and future modes are decoded without lifecycle rules',
    () async {
      handler = (request) async {
        request.response.write(
          jsonEncode({
            ..._sessionJson,
            'protection': 'future',
            'recipientMode': 'future',
            'new': true,
          }),
        );
        await request.response.close();
      };
      final session = await api.open(
        _shareId,
        'synthetic-access',
        cancelToken: CancelToken(),
      );
      expect(session.protection, 'future');
      expect(session.recipientMode, 'future');
    },
  );

  test('invalid JSON never exposes parser input', () async {
    handler = (request) async {
      request.response.write('synthetic-secret{broken');
      await request.response.close();
    };
    await expectLater(
      api.open(_shareId, 'synthetic-access', cancelToken: CancelToken()),
      _failure,
    );
  });

  test('missing fields fail deserialization with a redacted error', () async {
    handler = (request) async {
      request.response.write('{"sessionToken":"synthetic-sensitive"}');
      await request.response.close();
    };
    await expectLater(
      api.open(_shareId, 'synthetic-access', cancelToken: CancelToken()),
      _failure,
    );
  });

  test(
    'bounded metadata and ciphertext streams reject oversized responses',
    () async {
      handler = (request) async {
        request.response.write('x' * (513 * 1024));
        await request.response.close();
      };
      await expectLater(
        api.open(_shareId, 'synthetic-access', cancelToken: CancelToken()),
        _failure,
      );
      await expectLater(
        api.receive(_shareId, _session, cancelToken: CancelToken()),
        _failure,
      );
    },
  );

  test('pre-cancelled request never reaches the socket', () async {
    final token = CancelToken()..cancel('synthetic reason');
    await expectLater(
      api.open(_shareId, 'synthetic-access', cancelToken: token),
      _failure,
    );
    expect(requests, isEmpty);
  });

  test('invalid UTF-8 is redacted rather than normalized', () async {
    handler = (request) async {
      request.response.add([0xff, 0xfe]);
      await request.response.close();
    };
    await expectLater(
      api.open(_shareId, 'synthetic-access', cancelToken: CancelToken()),
      _failure,
    );
  });

  test(
    'cancellation also interrupts the streamed body after headers',
    () async {
      final flushed = Completer<void>();
      final release = Completer<void>();
      handler = (request) async {
        request.response.bufferOutput = false;
        request.response.write('{"sessionToken":"');
        await request.response.flush();
        flushed.complete();
        await release.future;
        await request.response.close();
      };
      final cancel = CancelToken();
      final result = api.open(
        _shareId,
        'synthetic-access',
        cancelToken: cancel,
      );
      final assertion = expectLater(result, _failure);
      await flushed.future;
      cancel.cancel();
      await assertion.timeout(const Duration(seconds: 2));
      release.complete();
      expect(requests.length, 1);
    },
  );

  test(
    'cancels a pending response without publishing a late session',
    () async {
      final reached = Completer<void>();
      final release = Completer<void>();
      handler = (request) async {
        reached.complete();
        await release.future;
        request.response.write(jsonEncode(_sessionJson));
        await request.response.close();
      };
      final cancel = CancelToken();
      final result = api.open(
        _shareId,
        'synthetic-access',
        cancelToken: cancel,
      );
      final assertion = expectLater(result, _failure);
      await reached.future;
      cancel.cancel();
      await assertion;
      release.complete();
      expect(requests.length, 1);
    },
  );
}
