import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/exceptions/vault_exceptions.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';

class _MockVaultRepository extends Mock implements VaultRepository {}

void main() {
  late _MockVaultRepository repository;

  final sampleVaults = <VaultEntity>[
    VaultEntity(
      id: 'v1',
      name: 'Personal',
      grantMode: GrantMode.granular,
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 20),
      entryCount: 7,
      activeGrantCount: 0,
      memberCount: 1,
    ),
    VaultEntity(
      id: 'v2',
      name: 'Work',
      grantMode: GrantMode.full,
      createdAt: DateTime.utc(2026, 3, 15),
      updatedAt: DateTime.utc(2026, 4, 10),
      entryCount: 12,
      activeGrantCount: 2,
      memberCount: 1,
    ),
  ];

  setUp(() {
    repository = _MockVaultRepository();
  });

  VaultListCubit buildCubit() => VaultListCubit(repository: repository);

  group('VaultListCubit', () {
    test('initial state is VaultListInitial', () {
      final cubit = buildCubit();
      expect(cubit.state, isA<VaultListInitial>());
      cubit.close();
    });

    blocTest<VaultListCubit, VaultListState>(
      'loadVaults emits Loading then Loaded on success',
      build: () {
        when(() => repository.listVaults())
            .thenAnswer((_) async => sampleVaults);
        return buildCubit();
      },
      act: (cubit) => cubit.loadVaults(),
      expect: () => [
        isA<VaultListLoading>(),
        isA<VaultListLoaded>().having(
          (s) => s.vaults.length,
          'vaults.length',
          2,
        ),
      ],
    );

    blocTest<VaultListCubit, VaultListState>(
      'loadVaults emits Loading then Loaded(empty) when no vaults',
      build: () {
        when(() => repository.listVaults())
            .thenAnswer((_) async => const <VaultEntity>[]);
        return buildCubit();
      },
      act: (cubit) => cubit.loadVaults(),
      expect: () => [
        isA<VaultListLoading>(),
        isA<VaultListLoaded>()
            .having((s) => s.vaults, 'vaults', isEmpty),
      ],
    );

    blocTest<VaultListCubit, VaultListState>(
      'loadVaults emits Loading then Error on VaultException',
      build: () {
        when(() => repository.listVaults())
            .thenThrow(const VaultException(VaultErrorKind.networkError));
        return buildCubit();
      },
      act: (cubit) => cubit.loadVaults(),
      expect: () => [
        isA<VaultListLoading>(),
        isA<VaultListError>().having(
          (s) => s.kind,
          'kind',
          VaultErrorKind.networkError,
        ),
      ],
    );

    blocTest<VaultListCubit, VaultListState>(
      'loadVaults wraps unexpected errors as VaultErrorKind.unknown',
      build: () {
        when(() => repository.listVaults()).thenThrow(StateError('boom'));
        return buildCubit();
      },
      act: (cubit) => cubit.loadVaults(),
      expect: () => [
        isA<VaultListLoading>(),
        isA<VaultListError>().having(
          (s) => s.kind,
          'kind',
          VaultErrorKind.unknown,
        ),
      ],
    );

    blocTest<VaultListCubit, VaultListState>(
      'deleteVault deletes then refreshes the list',
      build: () {
        when(() => repository.deleteVault(any())).thenAnswer((_) async {});
        when(() => repository.listVaults())
            .thenAnswer((_) async => sampleVaults.skip(1).toList());
        return buildCubit();
      },
      act: (cubit) => cubit.deleteVault('v1'),
      // The refresh's `emit(VaultListLoading())` is deduplicated by
      // Cubit because `const VaultListLoading()` is canonicalized —
      // identical instance, no event fired.
      expect: () => [
        isA<VaultListLoading>(),
        isA<VaultListLoaded>().having(
          (s) => s.vaults.single.id,
          'vaults.single.id',
          'v2',
        ),
      ],
      verify: (_) {
        verify(() => repository.deleteVault('v1')).called(1);
        verify(() => repository.listVaults()).called(1);
      },
    );

    blocTest<VaultListCubit, VaultListState>(
      'deleteVault surfaces error and does not refresh on VaultException',
      build: () {
        when(() => repository.deleteVault(any()))
            .thenThrow(const VaultException(VaultErrorKind.notFound));
        return buildCubit();
      },
      act: (cubit) => cubit.deleteVault('v1'),
      expect: () => [
        isA<VaultListLoading>(),
        isA<VaultListError>().having(
          (s) => s.kind,
          'kind',
          VaultErrorKind.notFound,
        ),
      ],
      verify: (_) {
        verifyNever(() => repository.listVaults());
      },
    );
  });
}
