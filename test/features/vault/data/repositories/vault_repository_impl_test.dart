import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/repositories/vault_repository_impl.dart';
import 'package:mobile_palladin/features/vault/domain/exceptions/vault_exceptions.dart';

class _MockDatasource extends Mock implements VaultRemoteDatasource {}

void main() {
  late _MockDatasource datasource;
  late VaultRepositoryImpl repository;

  setUp(() {
    datasource = _MockDatasource();
    repository = VaultRepositoryImpl(datasource);
  });

  DioException dioError({
    int? status,
    DioExceptionType type = DioExceptionType.badResponse,
    Map<String, dynamic>? body,
    Object? error,
  }) => DioException(
    requestOptions: RequestOptions(path: '/api/vaults/v1'),
    response: status == null
        ? null
        : Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/vaults/v1'),
            statusCode: status,
            data: body,
          ),
    type: type,
    error: error,
  );

  test('delete delegates to the datasource', () async {
    when(() => datasource.deleteVault('v1')).thenAnswer((_) async {});
    await repository.deleteVault('v1');
    verify(() => datasource.deleteVault('v1')).called(1);
  });

  group('delete error classification', () {
    Future<void> expectKind(DioException error, VaultErrorKind kind) async {
      when(() => datasource.deleteVault(any())).thenThrow(error);
      await expectLater(
        repository.deleteVault('v1'),
        throwsA(isA<VaultException>().having((e) => e.kind, 'kind', kind)),
      );
    }

    test(
      '404 maps to notFound',
      () => expectKind(dioError(status: 404), VaultErrorKind.notFound),
    );

    test(
      'unknown 403 maps to forbidden',
      () => expectKind(
        dioError(status: 403, body: const {'errorCode': 'other'}),
        VaultErrorKind.forbidden,
      ),
    );

    test(
      'connection timeout maps to networkError',
      () => expectKind(
        dioError(type: DioExceptionType.connectionTimeout),
        VaultErrorKind.networkError,
      ),
    );

    test(
      'SocketException maps to networkError',
      () => expectKind(
        dioError(
          type: DioExceptionType.unknown,
          error: const SocketException('boom'),
        ),
        VaultErrorKind.networkError,
      ),
    );

    test(
      '500 maps to unknown',
      () => expectKind(dioError(status: 500), VaultErrorKind.unknown),
    );
  });
}
