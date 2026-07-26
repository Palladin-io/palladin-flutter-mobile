import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';

class _RecordingAdapter implements HttpClientAdapter {
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
      jsonEncode({'state': 'Active', 'currentRevision': '9'}),
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
  test('restore sends only the versioned opaque transition payload', () async {
    final adapter = _RecordingAdapter();
    final datasource = EntryRemoteDatasource(
      Dio()..httpClientAdapter = adapter,
    );
    final payload = <String, dynamic>{
      'baseRevision': '8',
      'memberSecret': {'ciphertext': 'opaque-secret'},
      'memberIndex': {'ciphertext': 'opaque-index'},
      'agentDiscovery': {'ciphertext': 'opaque-discovery'},
    };

    await datasource.restoreCanonicalEntry('vault-id', 'entry-id', payload);

    expect(
      adapter.request?.path,
      '/api/vaults/vault-id/entries/entry-id/restore',
    );
    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.queryParameters, isEmpty);
    final wire = jsonDecode(utf8.decode(adapter.body)) as Map<String, dynamic>;
    expect(wire, payload);
    expect(
      wire.keys,
      isNot(containsAll(<String>['query', 'search', 'label', 'entryName'])),
    );
  });
}
