import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/datasources/member_sync_remote_datasource.dart';

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.response, {this.declaredContentLength});

  Map<String, dynamic> response;
  int? declaredContentLength;
  RequestOptions? request;
  List<int> body = const [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    if (requestStream != null) {
      body = await requestStream.expand((chunk) => chunk).toList();
    }
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (declaredContentLength != null)
          Headers.contentLengthHeader: ['$declaredContentLength'],
        'x-palladin-vault-protocol': ['2'],
        'x-palladin-sync-policy': ['2'],
        'content-encoding': ['identity'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Map<String, dynamic> snapshot;

  setUp(() {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/current_member_entry_sync_v2/valid-snapshot.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    snapshot = Map<String, dynamic>.from(fixture['response'] as Map);
  });

  test('uses only the frozen policy-2 snapshot route and headers', () async {
    final adapter = _RecordingAdapter(snapshot);
    final datasource = MemberSyncRemoteDatasource(
      Dio()..httpClientAdapter = adapter,
    );
    final vaultId = snapshot['accessContext']['vaultId'] as String;

    await datasource.snapshot(vaultId: vaultId);

    expect(
      adapter.request?.path,
      '/api/vaults/$vaultId/current-entries/sync/snapshot',
    );
    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.headers['X-Palladin-Vault-Protocol'], '2');
    expect(adapter.request?.headers['X-Palladin-Sync-Policy'], '2');
    final wire = jsonDecode(utf8.decode(adapter.body)) as Map<String, dynamic>;
    expect(wire, {'vaultId': vaultId, 'cursor': null, 'pageSize': 100});
    expect(wire, isNot(contains('includeSecrets')));
  });

  test(
    'uses one frozen policy-2 delta request with no projection fan-out',
    () async {
      final vaultId = snapshot['accessContext']['vaultId'] as String;
      final adapter = _RecordingAdapter({
        'deltaUpperBound': '12',
        'appliedThroughSequence': '12',
        'accessContext': snapshot['accessContext'],
        'memberVaultKey': snapshot['memberVaultKey'],
        'items': <Object?>[],
        'continuationCursor': null,
      });
      final datasource = MemberSyncRemoteDatasource(
        Dio()..httpClientAdapter = adapter,
      );

      await datasource.delta(vaultId: vaultId, afterSequence: '12');

      expect(
        adapter.request?.path,
        '/api/vaults/$vaultId/current-entries/sync/delta',
      );
      final wire =
          jsonDecode(utf8.decode(adapter.body)) as Map<String, dynamic>;
      expect(wire, {
        'vaultId': vaultId,
        'afterSequence': '12',
        'pageSize': 100,
      });
      expect(wire.keys, isNot(containsAll(['memberIndex', 'memberSecret'])));
    },
  );

  test('rejects a response declared above the frozen byte ceiling', () async {
    final adapter = _RecordingAdapter(
      snapshot,
      declaredContentLength: 4 * 1024 * 1024 + 1,
    );
    final datasource = MemberSyncRemoteDatasource(
      Dio()..httpClientAdapter = adapter,
    );

    await expectLater(
      datasource.snapshot(
        vaultId: snapshot['accessContext']['vaultId'] as String,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  for (final fraction in ['1234567', '123456789']) {
    test(
      'accepts backend Instant timestamps with ${fraction.length} fractional digits',
      () async {
        snapshot['accessContext']['issuedAt'] =
            '2026-09-19T17:00:00.${fraction}Z';
        snapshot['accessContext']['notAfter'] =
            '2026-09-19T18:00:00.${fraction}Z';
        final datasource = MemberSyncRemoteDatasource(
          Dio()..httpClientAdapter = _RecordingAdapter(snapshot),
        );

        final page = await datasource.snapshot(
          vaultId: snapshot['accessContext']['vaultId'] as String,
        );

        expect(
          page.accessContext.issuedAt,
          DateTime.utc(2026, 9, 19, 17, 0, 0, 123, 456),
        );
        expect(
          page.accessContext.notAfter,
          DateTime.utc(2026, 9, 19, 18, 0, 0, 123, 456),
        );
        expect(
          page.accessContext.notAfter.difference(page.accessContext.issuedAt),
          const Duration(hours: 1),
        );
      },
    );
  }
}
