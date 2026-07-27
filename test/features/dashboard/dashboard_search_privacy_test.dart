import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/dashboard/data/datasources/dashboard_remote_datasource.dart';

void main() {
  test('raw query is ephemeral POST body and never appears in URL', () async {
    late RequestOptions observed;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          observed = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: const {'results': <dynamic>[]},
              statusCode: 200,
            ),
          );
        },
      ),
    );

    await DashboardRemoteDatasource(
      dio,
    ).globalSearch('private vault words', 10, cancelToken: CancelToken());

    expect(observed.method, 'POST');
    expect(observed.uri.toString(), isNot(contains('private')));
    expect(observed.queryParameters, isEmpty);
    expect(observed.data, {'query': 'private vault words', 'limit': 10});
    expect(observed.headers.toString(), isNot(contains('private vault words')));
  });

  test(
    'Vault and Entry response types fail closed at remote boundary',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: const {
                  'results': [
                    {
                      'type': 'entry',
                      'organizationId': 'o1',
                      'id': 'e1',
                      'name': 'x',
                    },
                  ],
                },
                statusCode: 200,
              ),
            );
          },
        ),
      );
      expect(
        () => DashboardRemoteDatasource(
          dio,
        ).globalSearch('xx', 10, cancelToken: CancelToken()),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
