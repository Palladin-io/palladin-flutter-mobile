import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/exceptions/vault_exceptions.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_repository.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_list_crypto_service.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';

class _MockVaultRepository extends Mock implements VaultRepository {}

class _MockVaultListCryptoService extends Mock
    implements VaultListCryptoService {}

void main() {
  late _MockVaultRepository repository;
  late _MockVaultListCryptoService listService;
  final privateKey = Uint8List(32);

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
    listService = _MockVaultListCryptoService();
  });

  VaultListCubit buildCubit() =>
      VaultListCubit(repository: repository, listService: listService);

  group('VaultListCubit', () {
    test('initial state is VaultListInitial', () {
      final cubit = buildCubit();
      expect(cubit.state, isA<VaultListInitial>());
      cubit.close();
    });

    blocTest<VaultListCubit, VaultListState>(
      'loadVaults emits Loading then Loaded on success',
      build: () {
        when(() => listService.load(privateKey)).thenAnswer(
          (_) async =>
              DecryptedVaultList(vaults: sampleVaults, corruptIds: const []),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.loadVaults(privateKey),
      expect: () => [
        isA<VaultListLoading>(),
        isA<VaultListLoaded>().having(
          (s) => s.vaults.length,
          'vaults.length',
          2,
        ),
      ],
    );

    test('lock invalidates a late decrypted vault-list result', () async {
      final pending = Completer<DecryptedVaultList>();
      when(
        () => listService.load(privateKey),
      ).thenAnswer((_) => pending.future);
      final cubit = buildCubit();

      final load = cubit.loadVaults(privateKey);
      cubit.lock();
      pending.complete(
        DecryptedVaultList(vaults: sampleVaults, corruptIds: const []),
      );
      await load;

      expect(cubit.state, isA<VaultListLocked>());
      await cubit.close();
    });

    test('concurrent loadIfNeeded calls share one backend load', () async {
      final pending = Completer<DecryptedVaultList>();
      when(
        () => listService.load(privateKey),
      ).thenAnswer((_) => pending.future);
      final cubit = buildCubit();

      final first = cubit.loadIfNeeded(privateKey);
      final second = cubit.loadIfNeeded(privateKey);

      expect(identical(first, second), isTrue);
      pending.complete(
        DecryptedVaultList(vaults: sampleVaults, corruptIds: const []),
      );
      await Future.wait([first, second]);

      verify(() => listService.load(privateKey)).called(1);
      expect(cubit.state, isA<VaultListLoaded>());
      await cubit.close();
    });

    blocTest<VaultListCubit, VaultListState>(
      'loadVaults emits Loading then Loaded(empty) when no vaults',
      build: () {
        when(() => listService.load(privateKey)).thenAnswer(
          (_) async => const DecryptedVaultList(vaults: [], corruptIds: []),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.loadVaults(privateKey),
      expect: () => [
        isA<VaultListLoading>(),
        isA<VaultListLoaded>().having((s) => s.vaults, 'vaults', isEmpty),
      ],
    );

    blocTest<VaultListCubit, VaultListState>(
      'loadVaults emits Loading then Error on VaultException',
      build: () {
        when(
          () => listService.load(privateKey),
        ).thenThrow(const VaultException(VaultErrorKind.networkError));
        return buildCubit();
      },
      act: (cubit) => cubit.loadVaults(privateKey),
      expect: () => [
        isA<VaultListLoading>(),
        isA<VaultListError>().having(
          (s) => s.kind,
          'kind',
          VaultErrorKind.networkError,
        ),
      ],
    );

    test('member-index load propagates a typed network failure', () async {
      when(
        () => listService.load(privateKey),
      ).thenThrow(const VaultException(VaultErrorKind.networkError));
      final cubit = buildCubit();

      await expectLater(
        cubit.loadForMemberIndex(privateKey),
        throwsA(
          isA<VaultException>().having(
            (error) => error.kind,
            'kind',
            VaultErrorKind.networkError,
          ),
        ),
      );

      await cubit.close();
    });

    blocTest<VaultListCubit, VaultListState>(
      'loadVaults wraps unexpected errors as VaultErrorKind.unknown',
      build: () {
        when(() => listService.load(privateKey)).thenThrow(StateError('boom'));
        return buildCubit();
      },
      act: (cubit) => cubit.loadVaults(privateKey),
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
        when(() => listService.load(privateKey)).thenAnswer(
          (_) async =>
              DecryptedVaultList(vaults: sampleVaults, corruptIds: const []),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.deleteVault('v1'),
      // The refresh's `emit(VaultListLoading())` is deduplicated by
      // Cubit because `const VaultListLoading()` is canonicalized —
      // identical instance, no event fired.
      expect: () => [isA<VaultListLoading>(), isA<VaultListInitial>()],
      verify: (_) {
        verify(() => repository.deleteVault('v1')).called(1);
        verifyNever(() => listService.load(privateKey));
      },
    );

    blocTest<VaultListCubit, VaultListState>(
      'deleteVault surfaces error and does not refresh on VaultException',
      build: () {
        when(
          () => repository.deleteVault(any()),
        ).thenThrow(const VaultException(VaultErrorKind.notFound));
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
        verifyNever(() => listService.load(privateKey));
      },
    );
  });
}
