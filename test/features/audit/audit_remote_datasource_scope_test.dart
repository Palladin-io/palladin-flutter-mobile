import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/audit/data/datasources/audit_remote_datasource.dart';

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode({'items': <Object>[], 'nextCursor': null}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'Entry audit request sends only opaque structural scope and cursor',
    () async {
      final adapter = _RecordingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final datasource = AuditRemoteDatasource(dio);

      await datasource.listVaultLogs(
        '11111111-1111-4111-8111-111111111111',
        entryId: '22222222-2222-4222-8222-222222222222',
        cursor: 'opaque-cursor',
        pageSize: 50,
      );

      expect(
        adapter.request?.path,
        '/api/vaults/11111111-1111-4111-8111-111111111111/audit-logs',
      );
      expect(adapter.request?.queryParameters, {
        'entryId': '22222222-2222-4222-8222-222222222222',
        'cursor': 'opaque-cursor',
        'pageSize': 50,
      });
      expect(
        adapter.request?.queryParameters.keys,
        isNot(containsAll(<String>['query', 'search', 'content', 'entryName'])),
      );
    },
  );
}
