import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';

void main() {
  test('delete uses the recoverable lifecycle POST endpoint', () async {
    final dio = Dio();
    late RequestOptions request;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(Response(requestOptions: options, statusCode: 200));
        },
      ),
    );
    final material = {
      'baseRevision': '7',
      'memberSecret': {'ciphertext': 'encrypted'},
      'memberIndex': {'ciphertext': 'encrypted'},
    };
    await EntryRemoteDatasource(dio).deleteEntry('vault', 'entry', material);
    expect(request.data, same(material));
    expect(request.method, 'POST');
    expect(request.path, '/api/vaults/vault/entries/entry/delete');
  });
}
