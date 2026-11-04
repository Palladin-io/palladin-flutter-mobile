import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';

class _Transport implements HttpClientAdapter {
  final calls = <Completer<ResponseBody>>[];
  final arrivals = StreamController<void>.broadcast(sync: true);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    expect(options.method, 'GET');
    expect(options.path, '/api/account');
    final response = Completer<ResponseBody>();
    calls.add(response);
    arrivals.add(null);
    return response.future;
  }

  Future<void> waitFor(int count) async {
    while (calls.length < count) {
      await arrivals.stream.first;
    }
  }

  void respond(int index, String account, {int status = 200}) {
    calls[index].complete(
      ResponseBody.fromString(
        jsonEncode({'userId': account}),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {
    arrivals.close();
  }
}

void main() {
  late _Transport transport;
  late Dio dio;
  setUp(() {
    transport = _Transport();
    dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = transport;
  });
  tearDown(() => dio.close(force: true));

  test(
    'concurrent account reads share one request but completed result is not cached',
    () async {
      final source = AccountRemoteDatasource(dio, sessionRevision: () => 1);
      final first = source.getAccount();
      final second = source.getAccount();
      await transport.waitFor(1);
      // Complete all dispatched requests, so baseline duplicate requests also
      // settle and the observable request count identifies the regression.
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < transport.calls.length; i++) {
        transport.respond(i, 'first');
      }
      expect((await first).userId, 'first');
      expect((await second).userId, 'first');
      expect(transport.calls.length, 1);
      final next = source.getAccount();
      await transport.waitFor(2);
      transport.respond(1, 'updated');
      expect((await next).userId, 'updated');
    },
  );

  test('failed shared request can be retried', () async {
    final source = AccountRemoteDatasource(dio, sessionRevision: () => 1);
    final first = source.getAccount();
    final second = source.getAccount();
    final errors = Future.wait([
      expectLater(first, throwsA(isA<DioException>())),
      expectLater(second, throwsA(isA<DioException>())),
    ]);
    await transport.waitFor(1);
    transport.respond(0, 'failure', status: 503);
    await errors;
    final retry = source.getAccount();
    await transport.waitFor(2);
    transport.respond(1, 'recovered');
    expect((await retry).userId, 'recovered');
  });

  test(
    'new authority revision never shares old account request or loses its pending owner',
    () async {
      var revision = 1;
      final source = AccountRemoteDatasource(
        dio,
        sessionRevision: () => revision,
      );
      final old = source.getAccount();
      await transport.waitFor(1);
      revision = 2;
      final current = source.getAccount();
      await transport.waitFor(2);
      transport.respond(0, 'old-account');
      await old;
      final joined = source.getAccount();
      await Future<void>.delayed(Duration.zero);
      expect(
        transport.calls.length,
        2,
        reason: 'Old completion cleared the new request',
      );
      transport.respond(1, 'new-account');
      expect((await current).userId, 'new-account');
      expect((await joined).userId, 'new-account');
    },
  );

  test(
    'without independent revision authority requests are not shared',
    () async {
      final source = AccountRemoteDatasource(dio);
      final first = source.getAccount();
      final second = source.getAccount();
      await transport.waitFor(2);
      transport.respond(0, 'first-account');
      transport.respond(1, 'second-account');
      expect((await first).userId, 'first-account');
      expect((await second).userId, 'second-account');
    },
  );
  test(
    'only unlock reads may use protected fallback on connection failure',
    () async {
      var fallbackReads = 0;
      final source = AccountRemoteDatasource(
        dio,
        sessionRevision: () => 1,
        readProtectedUnlock: () async {
          fallbackReads++;
          return const AccountResponse(userId: 'member');
        },
      );
      final unlock = source.getUnlockAccount();
      final general = source.getAccount();
      final rejected = expectLater(general, throwsA(isA<DioException>()));
      await transport.waitFor(1);
      transport.calls.single.completeError(
        DioException(
          requestOptions: RequestOptions(path: '/api/account'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect((await unlock).userId, 'member');
      await rejected;
      expect(fallbackReads, 1);
      expect(transport.calls.length, 1);
    },
  );

  for (final status in [401, 403, 404, 500]) {
    test(
      'HTTP $status never falls back to protected account material',
      () async {
        var reads = 0;
        final source = AccountRemoteDatasource(
          dio,
          readProtectedUnlock: () async {
            reads++;
            return const AccountResponse(userId: 'member');
          },
        );
        final rejected = expectLater(
          source.getUnlockAccount(),
          throwsA(isA<DioException>()),
        );
        await transport.waitFor(1);
        transport.respond(0, 'failure', status: status);
        await rejected;
        expect(reads, 0);
      },
    );
  }

  test('session replacement rejects delayed protected fallback', () async {
    var revision = 1;
    final material = Completer<AccountResponse>();
    final entered = Completer<void>();
    final source = AccountRemoteDatasource(
      dio,
      sessionRevision: () => revision,
      readProtectedUnlock: () {
        entered.complete();
        return material.future;
      },
    );
    final rejected = expectLater(source.getUnlockAccount(), throwsStateError);
    await transport.waitFor(1);
    transport.calls.single.completeError(
      DioException(
        requestOptions: RequestOptions(path: '/api/account'),
        type: DioExceptionType.connectionError,
      ),
    );
    await entered.future;
    revision++;
    material.complete(const AccountResponse(userId: 'old'));
    await rejected;
  });
  for (final type in [
    DioExceptionType.badCertificate,
    DioExceptionType.cancel,
    DioExceptionType.unknown,
  ]) {
    test('$type never invokes offline fallback', () async {
      var reads = 0;
      final source = AccountRemoteDatasource(
        dio,
        readProtectedUnlock: () async {
          reads++;
          return const AccountResponse(userId: 'member');
        },
      );
      final rejected = expectLater(
        source.getUnlockAccount(),
        throwsA(isA<DioException>()),
      );
      await transport.waitFor(1);
      transport.calls.single.completeError(
        DioException(
          requestOptions: RequestOptions(path: '/api/account'),
          type: type,
        ),
      );
      await rejected;
      expect(reads, 0);
    });
  }
}
