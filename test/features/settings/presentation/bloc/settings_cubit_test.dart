import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_claw_vault/features/settings/domain/entities/api_key.dart';
import 'package:mobile_claw_vault/features/settings/domain/entities/org.dart';
import 'package:mobile_claw_vault/features/settings/domain/exceptions/settings_exceptions.dart';
import 'package:mobile_claw_vault/features/settings/domain/repositories/settings_repository.dart';
import 'package:mobile_claw_vault/features/settings/presentation/bloc/settings_cubit.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  late _MockSettingsRepository repository;

  const sampleOrg = Org(
    orgId: 'o1',
    name: 'Acme',
    planType: 'Pro',
    memberCount: 3,
  );

  final sampleKeys = <ApiKey>[
    ApiKey(
      apiKeyId: 'k1',
      name: 'Prod',
      status: ApiKeyStatus.active,
      createdAt: DateTime.utc(2026, 5, 1),
    ),
  ];

  setUp(() {
    repository = _MockSettingsRepository();
  });

  SettingsCubit buildCubit() => SettingsCubit(repository: repository);

  group('SettingsCubit.loadOrg', () {
    blocTest<SettingsCubit, SettingsState>(
      'emits loading then loaded on success',
      build: () {
        when(() => repository.getOrg()).thenAnswer((_) async => sampleOrg);
        return buildCubit();
      },
      act: (cubit) => cubit.loadOrg(),
      expect: () => [
        isA<SettingsState>()
            .having((s) => s.orgStatus, 'orgStatus', SectionStatus.loading),
        isA<SettingsState>()
            .having((s) => s.orgStatus, 'orgStatus', SectionStatus.loaded)
            .having((s) => s.org?.name, 'org.name', 'Acme'),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'emits loading then error on SettingsException',
      build: () {
        when(() => repository.getOrg())
            .thenThrow(const SettingsException(SettingsErrorKind.forbidden));
        return buildCubit();
      },
      act: (cubit) => cubit.loadOrg(),
      expect: () => [
        isA<SettingsState>()
            .having((s) => s.orgStatus, 'orgStatus', SectionStatus.loading),
        isA<SettingsState>()
            .having((s) => s.orgStatus, 'orgStatus', SectionStatus.error)
            .having((s) => s.orgError, 'orgError', SettingsErrorKind.forbidden),
      ],
    );
  });

  group('SettingsCubit.loadApiKeys', () {
    blocTest<SettingsCubit, SettingsState>(
      'emits loading then loaded with keys',
      build: () {
        when(() => repository.listApiKeys())
            .thenAnswer((_) async => sampleKeys);
        return buildCubit();
      },
      act: (cubit) => cubit.loadApiKeys(),
      expect: () => [
        isA<SettingsState>()
            .having((s) => s.keysStatus, 'keysStatus', SectionStatus.loading),
        isA<SettingsState>()
            .having((s) => s.keysStatus, 'keysStatus', SectionStatus.loaded)
            .having((s) => s.apiKeys.length, 'apiKeys.length', 1),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'emits error on network failure',
      build: () {
        when(() => repository.listApiKeys()).thenThrow(
          const SettingsException(SettingsErrorKind.networkError),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.loadApiKeys(),
      expect: () => [
        isA<SettingsState>()
            .having((s) => s.keysStatus, 'keysStatus', SectionStatus.loading),
        isA<SettingsState>()
            .having((s) => s.keysStatus, 'keysStatus', SectionStatus.error)
            .having(
              (s) => s.keysError,
              'keysError',
              SettingsErrorKind.networkError,
            ),
      ],
    );
  });

  group('SettingsCubit.saveOrgName', () {
    blocTest<SettingsCubit, SettingsState>(
      'patches the cached org and flags success',
      build: () {
        when(() => repository.getOrg()).thenAnswer((_) async => sampleOrg);
        when(() => repository.updateOrgName(any())).thenAnswer((_) async {});
        return buildCubit();
      },
      seed: () => const SettingsState(
        orgStatus: SectionStatus.loaded,
        org: sampleOrg,
      ),
      act: (cubit) => cubit.saveOrgName('  Renamed  '),
      expect: () => [
        isA<SettingsState>().having((s) => s.isSavingOrg, 'isSavingOrg', true),
        isA<SettingsState>()
            .having((s) => s.isSavingOrg, 'isSavingOrg', false)
            .having((s) => s.org?.name, 'org.name', 'Renamed')
            .having((s) => s.orgSaveSucceeded, 'orgSaveSucceeded', true),
      ],
      verify: (_) {
        // Name must be trimmed before hitting the API.
        verify(() => repository.updateOrgName('Renamed')).called(1);
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'flags orgSaveError on failure',
      build: () {
        when(() => repository.updateOrgName(any())).thenThrow(
          const SettingsException(SettingsErrorKind.validation),
        );
        return buildCubit();
      },
      seed: () => const SettingsState(
        orgStatus: SectionStatus.loaded,
        org: sampleOrg,
      ),
      act: (cubit) => cubit.saveOrgName('Bad'),
      expect: () => [
        isA<SettingsState>().having((s) => s.isSavingOrg, 'isSavingOrg', true),
        isA<SettingsState>()
            .having((s) => s.isSavingOrg, 'isSavingOrg', false)
            .having(
              (s) => s.orgSaveError,
              'orgSaveError',
              SettingsErrorKind.validation,
            ),
      ],
    );
  });

  group('SettingsCubit.createApiKey', () {
    test('returns the one-time plaintext and refreshes the list', () async {
      when(() => repository.createApiKey(any()))
          .thenAnswer((_) async => _newKeyFixture());
      when(() => repository.listApiKeys())
          .thenAnswer((_) async => sampleKeys);

      final cubit = buildCubit();
      final created = await cubit.createApiKey('  New  ');

      expect(created.plaintext, 'cv_secret');
      // Name must be trimmed before hitting the API.
      verify(() => repository.createApiKey('New')).called(1);
      verify(() => repository.listApiKeys()).called(1);
      // SECURITY: the plaintext must never be persisted on cubit state.
      expect(cubit.state.apiKeys.any((k) => k.name == 'cv_secret'), isFalse);
      await cubit.close();
    });

    test('propagates SettingsException to the caller', () async {
      when(() => repository.createApiKey(any())).thenThrow(
        const SettingsException(SettingsErrorKind.validation),
      );
      final cubit = buildCubit();
      await expectLater(
        cubit.createApiKey('x'),
        throwsA(isA<SettingsException>()),
      );
      await cubit.close();
    });
  });

  group('SettingsCubit.revokeApiKey', () {
    blocTest<SettingsCubit, SettingsState>(
      'revokes then refreshes the list',
      build: () {
        when(() => repository.revokeApiKey(any())).thenAnswer((_) async {});
        when(() => repository.listApiKeys())
            .thenAnswer((_) async => const <ApiKey>[]);
        return buildCubit();
      },
      act: (cubit) => cubit.revokeApiKey('k1'),
      verify: (_) {
        verify(() => repository.revokeApiKey('k1')).called(1);
        verify(() => repository.listApiKeys()).called(1);
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'surfaces error and does not refresh on failure',
      build: () {
        when(() => repository.revokeApiKey(any())).thenThrow(
          const SettingsException(SettingsErrorKind.notFound),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.revokeApiKey('k1'),
      expect: () => [
        isA<SettingsState>()
            .having((s) => s.keysStatus, 'keysStatus', SectionStatus.error)
            .having((s) => s.keysError, 'keysError', SettingsErrorKind.notFound),
      ],
      verify: (_) {
        verifyNever(() => repository.listApiKeys());
      },
    );
  });
}

NewApiKey _newKeyFixture() => NewApiKey(
      apiKeyId: 'k9',
      name: 'New',
      plaintext: 'cv_secret',
      createdAt: DateTime.utc(2026, 5, 17),
    );
