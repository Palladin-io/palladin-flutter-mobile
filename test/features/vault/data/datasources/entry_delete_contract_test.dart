import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/core/network/auth_interceptor.dart';

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
    bool isSessionCurrent() => true;
    await EntryRemoteDatasource(dio).deleteEntry(
      'vault',
      'entry',
      material,
      isSessionCurrent: isSessionCurrent,
    );
    expect(request.data, same(material));
    expect(
      request.extra[AuthInterceptor.sessionGuardKey],
      same(isSessionCurrent),
    );
    expect(request.method, 'POST');
    expect(request.path, '/api/vaults/vault/entries/entry/delete');
  });
}
