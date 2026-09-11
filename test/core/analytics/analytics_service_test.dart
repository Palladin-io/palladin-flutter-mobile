import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';

class CaptureAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> payloads = [];
  final List<RequestOptions> requests = [];
  Completer<ResponseBody>? response;
  bool cancelled = false;
  final received = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = await requestStream!.expand((chunk) => chunk).toList();
    payloads.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    cancelFuture?.then((_) {
      cancelled = true;
    });
    if (!received.isCompleted) received.complete();
    return response == null
        ? ResponseBody.fromString(
            '{}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          )
        : response!.future;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AnalyticsService analytics;
  late CaptureAdapter adapter;
  late DateTime now;
  setUp(() {
    adapter = CaptureAdapter();
    now = DateTime.utc(2026, 9, 12);
    analytics = AnalyticsService(
      transport: Dio()..httpClientAdapter = adapter,
      now: () => now,
      uuid: () => 'memory-session',
    );
    analytics.configure(
      projectKey: 'test-project',
      host: 'https://eu.i.posthog.com',
      released: true,
    );
  });
  tearDown(() async => analytics.reset());
  void authorize([bool activated = true]) => analytics.authorize(
    'account',
    now.add(const Duration(seconds: 60)),
    () => activated,
  );

  test(
    'configuration alone never creates identifiers or sends traffic',
    () async {
      await analytics.capture('unlock', 'biometric-used');
      await analytics.pageview('/settings/privacy');
      expect(await analytics.getSessionId(), isNull);
      expect(adapter.requests, isEmpty);
      authorize(false);
      await analytics.capture('unlock', 'biometric-used');
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'release flag and EU destination are required independently of account consent',
    () async {
      for (final config in [
        (false, 'https://eu.i.posthog.com'),
        (true, 'https://us.i.posthog.com'),
      ]) {
        analytics.configure(
          projectKey: 'test-project',
          host: config.$2,
          released: config.$1,
        );
        authorize();
        await analytics.capture('unlock', 'biometric-used');
      }
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'final encoded payload omits all caller properties and duplicate backend outcomes',
    () async {
      authorize();
      await analytics.capture(
        'unlock',
        'biometric-used',
        properties: {'password': 'never-send', 'email': 'secret@example.test'},
      );
      await analytics.capture('recovery', 'recovery-completed');
      await analytics.capture('unlock', 'page-viewed');
      await analytics.pageview('/vaults/:vaultId');
      expect(adapter.payloads, hasLength(2));
      expect(
        adapter.requests.first.uri.toString(),
        'https://eu.i.posthog.com/i/v0/e/',
      );
      expect(adapter.requests.first.followRedirects, isFalse);
      expect(adapter.payloads.first, {
        'api_key': 'test-project',
        'event': 'mb:unlock:biometric-used',
        'distinct_id': 'account',
        'timestamp': now.toIso8601String(),
        'properties': {
          r'$session_id': 'memory-session',
          r'$process_person_profile': false,
          r'$geoip_disable': true,
        },
      });
    },
  );
  test('expired authority drops events without replay after refresh', () async {
    authorize();
    now = now.add(const Duration(seconds: 61));
    await analytics.capture('unlock', 'biometric-used');
    authorize();
    expect(adapter.requests, isEmpty);
    expect(await analytics.getSessionId(), isNull);
  });
  test(
    'withdrawal fences queued work and cancels requests already in flight',
    () async {
      authorize();
      final queued = analytics.capture('unlock', 'biometric-used');
      await analytics.reset();
      await queued;
      expect(adapter.requests, isEmpty);
      adapter.response = Completer<ResponseBody>();
      authorize();
      final sending = analytics.capture('unlock', 'biometric-used');
      await adapter.received.future;
      await analytics.reset();
      await sending;
      expect(adapter.cancelled, isTrue);
      expect(await analytics.getSessionId(), isNull);
      adapter.response!.complete(ResponseBody.fromString('{}', 200));
    },
  );
}
