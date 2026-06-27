import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/exceptions/vault_exceptions.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/create_vault_cubit.dart';

class _MockRepository extends Mock implements VaultRepository {}

class _MockCryptoService extends Mock implements VaultCryptoService {}

void main() {
  late _MockRepository repository;
  late _MockCryptoService crypto;

  final fakeVault = VaultEntity(
    id: 'new-vault',
    name: 'Created',
    grantMode: GrantMode.granular,
    createdAt: DateTime.utc(2026, 4, 25),
    updatedAt: DateTime.utc(2026, 4, 25),
    entryCount: 0,
    activeGrantCount: 0,
    memberCount: 1,
  );

  final privateKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  setUpAll(() {
    registerFallbackValue(GrantMode.granular);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    repository = _MockRepository();
    crypto = _MockCryptoService();
  });

  CreateVaultCubit buildCubit() => CreateVaultCubit(
        repository: repository,
        cryptoService: crypto,
      );

  group('CreateVaultCubit', () {
    test('initial state is CreateVaultInitial', () {
      final cubit = buildCubit();
      expect(cubit.state, isA<CreateVaultInitial>());
      cubit.close();
    });

    blocTest<CreateVaultCubit, CreateVaultState>(
      'createVault emits Error.unknown on empty name',
      build: buildCubit,
      act: (cubit) => cubit.createVault(
        name: '   ',
        grantMode: GrantMode.granular,
        privateKey: privateKey,
      ),
      expect: () => [
        isA<CreateVaultError>().having(
          (s) => s.kind,
          'kind',
          VaultErrorKind.unknown,
        ),
      ],
      verify: (_) {
        verifyNever(() => crypto.generateWrappedVK(any()));
        verifyNever(() => repository.createVault(
              name: any(named: 'name'),
              grantMode: any(named: 'grantMode'),
              wrappedVK: any(named: 'wrappedVK'),
            ));
      },
    );

    blocTest<CreateVaultCubit, CreateVaultState>(
      'createVault emits Error.unknown on empty private key',
      build: buildCubit,
      act: (cubit) => cubit.createVault(
        name: 'Personal',
        grantMode: GrantMode.granular,
        privateKey: Uint8List(0),
      ),
      expect: () => [
        isA<CreateVaultError>().having(
          (s) => s.kind,
          'kind',
          VaultErrorKind.unknown,
        ),
      ],
    );

    blocTest<CreateVaultCubit, CreateVaultState>(
      'createVault emits Loading then Success on happy path',
      build: () {
        when(() => crypto.generateWrappedVK(any()))
            .thenAnswer((_) async => 'wrapped-base64');
        when(() => repository.createVault(
              name: any(named: 'name'),
              description: any(named: 'description'),
              icon: any(named: 'icon'),
              color: any(named: 'color'),
              grantMode: any(named: 'grantMode'),
              wrappedVK: any(named: 'wrappedVK'),
            )).thenAnswer((_) async => fakeVault);
        return buildCubit();
      },
      act: (cubit) => cubit.createVault(
        name: 'Personal',
        description: 'desc',
        icon: '🔒',
        color: '#48ECDF',
        grantMode: GrantMode.granular,
        privateKey: privateKey,
      ),
      expect: () => [
        isA<CreateVaultLoading>(),
        isA<CreateVaultSuccess>().having(
          (s) => s.vault.id,
          'vault.id',
          'new-vault',
        ),
      ],
      verify: (_) {
        verify(() => crypto.generateWrappedVK(any())).called(1);
        verify(() => repository.createVault(
              name: 'Personal',
              description: 'desc',
              icon: '🔒',
              color: '#48ECDF',
              grantMode: GrantMode.granular,
              wrappedVK: 'wrapped-base64',
            )).called(1);
      },
    );

    blocTest<CreateVaultCubit, CreateVaultState>(
      'createVault propagates VaultException kind into Error state',
      build: () {
        when(() => crypto.generateWrappedVK(any()))
            .thenAnswer((_) async => 'wrapped');
        when(() => repository.createVault(
              name: any(named: 'name'),
              description: any(named: 'description'),
              icon: any(named: 'icon'),
              color: any(named: 'color'),
              grantMode: any(named: 'grantMode'),
              wrappedVK: any(named: 'wrappedVK'),
            )).thenThrow(
          const VaultException(VaultErrorKind.planLimitReached),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.createVault(
        name: 'Personal',
        grantMode: GrantMode.granular,
        privateKey: privateKey,
      ),
      expect: () => [
        isA<CreateVaultLoading>(),
        isA<CreateVaultError>().having(
          (s) => s.kind,
          'kind',
          VaultErrorKind.planLimitReached,
        ),
      ],
    );

    blocTest<CreateVaultCubit, CreateVaultState>(
      'reset returns to Initial only when state is non-initial',
      build: () {
        when(() => crypto.generateWrappedVK(any()))
            .thenAnswer((_) async => 'wrapped');
        when(() => repository.createVault(
              name: any(named: 'name'),
              description: any(named: 'description'),
              icon: any(named: 'icon'),
              color: any(named: 'color'),
              grantMode: any(named: 'grantMode'),
              wrappedVK: any(named: 'wrappedVK'),
            )).thenAnswer((_) async => fakeVault);
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.createVault(
          name: 'Personal',
          grantMode: GrantMode.granular,
          privateKey: privateKey,
        );
        cubit.reset();
        cubit.reset(); // second call is a no-op
      },
      expect: () => [
        isA<CreateVaultLoading>(),
        isA<CreateVaultSuccess>(),
        isA<CreateVaultInitial>(),
      ],
    );
  });
}
