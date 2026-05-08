import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_claw_vault/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_claw_vault/features/vault/data/models/create_vault_request.dart';
import 'package:mobile_claw_vault/features/vault/data/repositories/vault_repository_impl.dart';
import 'package:mobile_claw_vault/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_claw_vault/features/vault/domain/exceptions/vault_exceptions.dart';

class _MockDatasource extends Mock implements VaultRemoteDatasource {}

class _FakeCreateVaultRequest extends Fake implements CreateVaultRequest {}

class _FakeUpdateVaultRequest extends Fake implements UpdateVaultRequest {}

void main() {
  late _MockDatasource datasource;
  late VaultRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(_FakeCreateVaultRequest());
    registerFallbackValue(_FakeUpdateVaultRequest());
  });

  setUp(() {
    datasource = _MockDatasource();
    repository = VaultRepositoryImpl(datasource);
  });

  DioException dioError({
    int? status,
    DioExceptionType type = DioExceptionType.badResponse,
    Map<String, dynamic>? body,
    Object? error,
  }) {
    return DioException(
      requestOptions: RequestOptions(path: '/api/vaults'),
      response: status == null
          ? null
          : Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/vaults'),
              statusCode: status,
              data: body,
            ),
      type: type,
      error: error,
    );
  }

  group('VaultRepositoryImpl error classification', () {
    test('404 → VaultErrorKind.notFound', () async {
      when(() => datasource.getVault(any())).thenThrow(dioError(status: 404));
      try {
        await repository.getVault('v1');
        fail('expected VaultException');
      } on VaultException catch (e) {
        expect(e.kind, VaultErrorKind.notFound);
      }
    });

    test('403 with plan-limit body → planLimitReached', () async {
      when(() => datasource.createVault(any())).thenThrow(
        dioError(
          status: 403,
          body: const {'errorCode': 'plan_limit_reached'},
        ),
      );
      try {
        await repository.createVault(
          name: 'New',
          grantMode: GrantMode.granular,
          wrappedVK: 'wrapped',
        );
        fail('expected VaultException');
      } on VaultException catch (e) {
        expect(e.kind, VaultErrorKind.planLimitReached);
      }
    });

    test('403 with full-mode body → fullModeNotAllowed', () async {
      when(() => datasource.createVault(any())).thenThrow(
        dioError(
          status: 403,
          body: const {'errorCode': 'full_mode_not_allowed'},
        ),
      );
      try {
        await repository.createVault(
          name: 'New',
          grantMode: GrantMode.full,
          wrappedVK: 'wrapped',
        );
        fail('expected VaultException');
      } on VaultException catch (e) {
        expect(e.kind, VaultErrorKind.fullModeNotAllowed);
      }
    });

    test('403 with no recognised body → forbidden', () async {
      when(() => datasource.deleteVault(any())).thenThrow(
        dioError(status: 403, body: const {'errorCode': 'something_else'}),
      );
      try {
        await repository.deleteVault('v1');
        fail('expected VaultException');
      } on VaultException catch (e) {
        expect(e.kind, VaultErrorKind.forbidden);
      }
    });

    test('connection timeout → networkError', () async {
      when(() => datasource.listVaults()).thenThrow(
        dioError(type: DioExceptionType.connectionTimeout),
      );
      try {
        await repository.listVaults();
        fail('expected VaultException');
      } on VaultException catch (e) {
        expect(e.kind, VaultErrorKind.networkError);
      }
    });

    test('SocketException → networkError', () async {
      when(() => datasource.listVaults()).thenThrow(
        dioError(
          type: DioExceptionType.unknown,
          error: const SocketException('boom'),
        ),
      );
      try {
        await repository.listVaults();
        fail('expected VaultException');
      } on VaultException catch (e) {
        expect(e.kind, VaultErrorKind.networkError);
      }
    });

    test('500 → unknown', () async {
      when(() => datasource.listVaults()).thenThrow(dioError(status: 500));
      try {
        await repository.listVaults();
        fail('expected VaultException');
      } on VaultException catch (e) {
        expect(e.kind, VaultErrorKind.unknown);
      }
    });
  });
}
