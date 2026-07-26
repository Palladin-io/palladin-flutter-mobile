import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/approval/data/datasources/approval_remote_datasource.dart';

void main() {
  test('deny sends no request body', () async {
    Object? body = Object();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            body = options.data;
            handler.resolve(
              Response<void>(requestOptions: options, statusCode: 204),
            );
          },
        ),
      );

    await ApprovalRemoteDatasource(
      dio,
    ).denyGrant(vaultId: 'vault', grantId: 'grant');

    expect(body, isNull);
  });
}
