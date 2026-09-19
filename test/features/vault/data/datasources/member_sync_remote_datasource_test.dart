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

  test(
    'additive API metadata and nanosecond timestamps keep sync readable',
    () async {
      snapshot['displayCount'] = 0;
      snapshot['accessContext']['futureMetadata'] = 'accepted';
      snapshot['accessContext']['issuedAt'] = '2026-09-19T12:00:00.123456789Z';
      final items = snapshot['items'] as List;
      for (final item in items) {
        item['futureMetadata'] = true;
      }
      final adapter = _RecordingAdapter(snapshot);
      final datasource = MemberSyncRemoteDatasource(
        Dio()..httpClientAdapter = adapter,
      );
      final page = await datasource.snapshot(
        vaultId: snapshot['accessContext']['vaultId'] as String,
      );
      expect(page.items.length, items.length);
    },
  );

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
}
