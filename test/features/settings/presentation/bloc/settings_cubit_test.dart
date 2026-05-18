import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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
}
