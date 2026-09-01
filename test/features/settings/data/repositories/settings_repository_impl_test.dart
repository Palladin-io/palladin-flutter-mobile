import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/settings/data/datasources/settings_remote_data_source.dart';
import 'package:mobile_palladin/features/settings/data/models/api_key_model.dart';
import 'package:mobile_palladin/features/settings/data/models/org_model.dart';
import 'package:mobile_palladin/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:mobile_palladin/features/settings/domain/entities/api_key.dart';
import 'package:mobile_palladin/features/settings/domain/exceptions/settings_exceptions.dart';

class _MockDataSource extends Mock implements SettingsRemoteDataSource {}

void main() {
  late _MockDataSource dataSource;
  late SettingsRepositoryImpl repository;

  setUp(() {
    dataSource = _MockDataSource();
    repository = SettingsRepositoryImpl(dataSource);
  });

  DioException dioError({
    int? status,
    DioExceptionType type = DioExceptionType.badResponse,
    Object? error,
    Object? data,
  }) {
    return DioException(
      requestOptions: RequestOptions(path: '/api/org'),
      response: status == null
          ? null
          : Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/org'),
              statusCode: status,
              data: data,
            ),
      type: type,
      error: error,
    );
  }

  group('SettingsRepositoryImpl error classification', () {
    test('404 → SettingsErrorKind.notFound', () async {
      when(() => dataSource.getOrg()).thenThrow(dioError(status: 404));
      try {
        await repository.getOrg();
        fail('expected SettingsException');
      } on SettingsException catch (e) {
        expect(e.kind, SettingsErrorKind.notFound);
      }
    });

    test('403 → SettingsErrorKind.forbidden', () async {
      when(() => dataSource.getOrg()).thenThrow(dioError(status: 403));
      try {
        await repository.getOrg();
        fail('expected SettingsException');
      } on SettingsException catch (e) {
        expect(e.kind, SettingsErrorKind.forbidden);
      }
    });

    test('400 → SettingsErrorKind.validation', () async {
      when(
        () => dataSource.updateOrgName(any()),
      ).thenThrow(dioError(status: 400));
      try {
        await repository.updateOrgName('x');
        fail('expected SettingsException');
      } on SettingsException catch (e) {
        expect(e.kind, SettingsErrorKind.validation);
      }
    });

    test('connection error → SettingsErrorKind.networkError', () async {
      when(
        () => dataSource.listApiKeys(),
      ).thenThrow(dioError(type: DioExceptionType.connectionError));
      try {
        await repository.listApiKeys();
        fail('expected SettingsException');
      } on SettingsException catch (e) {
        expect(e.kind, SettingsErrorKind.networkError);
      }
    });

    test('SocketException → SettingsErrorKind.networkError', () async {
      when(
        () => dataSource.listApiKeys(),
      ).thenThrow(dioError(error: const SocketException('offline')));
      try {
        await repository.listApiKeys();
        fail('expected SettingsException');
      } on SettingsException catch (e) {
        expect(e.kind, SettingsErrorKind.networkError);
      }
    });

    test('500 → SettingsErrorKind.unknown', () async {
      when(() => dataSource.getOrg()).thenThrow(dioError(status: 500));
      try {
        await repository.getOrg();
        fail('expected SettingsException');
      } on SettingsException catch (e) {
        expect(e.kind, SettingsErrorKind.unknown);
      }
    });

    test('GrantManage cutover 409 maps to the fail-closed error', () async {
      when(
        () => dataSource.updateOrganizationRole(any(), any(), any()),
      ).thenThrow(
        dioError(
          status: 409,
          data: {
            'errors': [
              {'code': 'organization-role-grant-manage-cutover-unavailable'},
            ],
          },
        ),
      );

      await expectLater(
        repository.updateOrganizationRole('role-1', 'Manager', 32),
        throwsA(
          isA<SettingsException>().having(
            (error) => error.kind,
            'kind',
            SettingsErrorKind.grantManageCutoverUnavailable,
          ),
        ),
      );
    });

    test('seat limit 409 maps to the capacity-specific error', () async {
      when(() => dataSource.inviteOrganizationMember(any(), any())).thenThrow(
        dioError(
          status: 409,
          data: {
            'errors': [
              {'code': 'organization-seat-limit-reached'},
            ],
          },
        ),
      );

      await expectLater(
        repository.inviteOrganizationMember('member@example.com', 'role-1'),
        throwsA(
          isA<SettingsException>().having(
            (error) => error.kind,
            'kind',
            SettingsErrorKind.seatLimitReached,
          ),
        ),
      );
    });

    test('unrelated 409 remains a generic conflict', () async {
      when(() => dataSource.deleteOrganizationRole(any())).thenThrow(
        dioError(
          status: 409,
          data: {
            'code': 'role-in-use',
            'detail': 'organization-role-grant-manage-cutover-unavailable',
          },
        ),
      );

      await expectLater(
        repository.deleteOrganizationRole('role-1'),
        throwsA(
          isA<SettingsException>().having(
            (error) => error.kind,
            'kind',
            SettingsErrorKind.conflict,
          ),
        ),
      );
    });
  });

  group('SettingsRepositoryImpl happy path', () {
    test('getOrg maps the model to a domain entity', () async {
      when(() => dataSource.getOrg()).thenAnswer(
        (_) async => const OrgModel(
          orgId: 'o1',
          name: 'Acme',
          planType: 'Pro',
          memberCount: 3,
          seatUsage: 4,
          seatLimit: 5,
        ),
      );
      final org = await repository.getOrg();
      expect(org.orgId, 'o1');
      expect(org.name, 'Acme');
      expect(org.planType, 'Pro');
      expect(org.memberCount, 3);
      expect(org.seatUsage, 4);
      expect(org.seatLimit, 5);
    });

    test('listApiKeys maps every model to a domain entity', () async {
      when(() => dataSource.listApiKeys()).thenAnswer(
        (_) async => [
          ApiKeyModel(
            apiKeyId: 'k1',
            name: 'Prod',
            keySuffix: 'aB3x',
            status: 'Active',
            createdAt: '2026-05-01T10:00:00Z',
          ),
          ApiKeyModel(
            apiKeyId: 'k2',
            name: 'Old',
            keySuffix: 'zQ9w',
            status: 'Revoked',
            createdAt: '2026-04-01T10:00:00Z',
            revokedAt: '2026-04-15T10:00:00Z',
          ),
        ],
      );
      final keys = await repository.listApiKeys();
      expect(keys, hasLength(2));
      expect(keys.first.status, ApiKeyStatus.active);
      expect(keys.last.status, ApiKeyStatus.revoked);
      expect(keys.last.revokedAt, isNotNull);
    });

    test('createApiKey returns the one-time plaintext', () async {
      when(() => dataSource.createApiKey(any())).thenAnswer(
        (_) async => const NewApiKeyModel(
          apiKeyId: 'k9',
          name: 'New',
          plaintext: 'pl_secret_value',
          createdAt: '2026-05-17T10:00:00Z',
        ),
      );
      final created = await repository.createApiKey('New');
      expect(created.plaintext, 'pl_secret_value');
      expect(created.apiKeyId, 'k9');
    });

    test('revokeApiKey delegates to the data source', () async {
      when(() => dataSource.revokeApiKey(any())).thenAnswer((_) async {});
      await repository.revokeApiKey('k1');
      verify(() => dataSource.revokeApiKey('k1')).called(1);
    });
  });
}
