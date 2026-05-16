import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_claw_vault/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_claw_vault/features/vault/domain/exceptions/entry_exceptions.dart';
import 'package:mobile_claw_vault/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_claw_vault/features/vault/presentation/cubit/create_entry_cubit.dart';

class _MockRepository extends Mock implements EntryRepository {}

void main() {
  late _MockRepository repository;

  final fakeEntry = EntryEntity(
    id: 'e-new',
    vaultId: 'v-1',
    label: 'Stripe API Key',
    type: EntryType.key,
    urlDomain: null,
    createdAt: DateTime.utc(2026, 4, 25),
    updatedAt: DateTime.utc(2026, 4, 25),
  );

  final privateKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  setUpAll(() {
    registerFallbackValue(EntryType.credential);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    repository = _MockRepository();
  });

  CreateEntryCubit buildCubit() => CreateEntryCubit(repository: repository);

  group('CreateEntryCubit', () {
    test('initial state is CreateEntryInitial', () {
      final cubit = buildCubit();
      expect(cubit.state, isA<CreateEntryInitial>());
      cubit.close();
    });

    blocTest<CreateEntryCubit, CreateEntryState>(
      'createEntry emits Error.unknown on empty label',
      build: buildCubit,
      act: (cubit) => cubit.createEntry(
        vaultId: 'v-1',
        label: '   ',
        type: EntryType.key,
        payload: const {'type': 'KEY', 'value': 'x'},
        privateKey: privateKey,
      ),
      expect: () => [
        isA<CreateEntryError>().having(
          (s) => s.kind,
          'kind',
          EntryErrorKind.unknown,
        ),
      ],
      verify: (_) {
        verifyNever(() => repository.createEntryEncrypted(
              vaultId: any(named: 'vaultId'),
              label: any(named: 'label'),
              type: any(named: 'type'),
              payload: any(named: 'payload'),
              privateKey: any(named: 'privateKey'),
            ));
      },
    );

    blocTest<CreateEntryCubit, CreateEntryState>(
      'createEntry emits Error.unknown on empty private key',
      build: buildCubit,
      act: (cubit) => cubit.createEntry(
        vaultId: 'v-1',
        label: 'Stripe',
        type: EntryType.key,
        payload: const {'type': 'KEY', 'value': 'x'},
        privateKey: Uint8List(0),
      ),
      expect: () => [
        isA<CreateEntryError>().having(
          (s) => s.kind,
          'kind',
          EntryErrorKind.unknown,
        ),
      ],
    );

    blocTest<CreateEntryCubit, CreateEntryState>(
      'createEntry emits Loading then Success on happy path',
      build: () {
        when(() => repository.createEntryEncrypted(
              vaultId: any(named: 'vaultId'),
              label: any(named: 'label'),
              description: any(named: 'description'),
              icon: any(named: 'icon'),
              type: any(named: 'type'),
              payload: any(named: 'payload'),
              urlDomain: any(named: 'urlDomain'),
              privateKey: any(named: 'privateKey'),
            )).thenAnswer((_) async => fakeEntry);
        return buildCubit();
      },
      act: (cubit) => cubit.createEntry(
        vaultId: 'v-1',
        label: 'Stripe API Key',
        description: 'prod',
        icon: 'code',
        type: EntryType.key,
        payload: const {'type': 'KEY', 'value': 'sk_live_xxx'},
        privateKey: privateKey,
      ),
      expect: () => [
        isA<CreateEntryLoading>(),
        isA<CreateEntrySuccess>().having(
          (s) => s.entry.id,
          'entry.id',
          'e-new',
        ),
      ],
      verify: (_) {
        verify(() => repository.createEntryEncrypted(
              vaultId: 'v-1',
              label: 'Stripe API Key',
              description: 'prod',
              icon: 'code',
              type: EntryType.key,
              payload: const {'type': 'KEY', 'value': 'sk_live_xxx'},
              urlDomain: null,
              privateKey: privateKey,
            )).called(1);
      },
    );

    blocTest<CreateEntryCubit, CreateEntryState>(
      'createEntry propagates EntryException kind into Error state',
      build: () {
        when(() => repository.createEntryEncrypted(
              vaultId: any(named: 'vaultId'),
              label: any(named: 'label'),
              description: any(named: 'description'),
              icon: any(named: 'icon'),
              type: any(named: 'type'),
              payload: any(named: 'payload'),
              urlDomain: any(named: 'urlDomain'),
              privateKey: any(named: 'privateKey'),
            )).thenThrow(
          const EntryException(EntryErrorKind.cryptoFailure),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.createEntry(
        vaultId: 'v-1',
        label: 'Stripe',
        type: EntryType.key,
        payload: const {'type': 'KEY', 'value': 'x'},
        privateKey: privateKey,
      ),
      expect: () => [
        isA<CreateEntryLoading>(),
        isA<CreateEntryError>().having(
          (s) => s.kind,
          'kind',
          EntryErrorKind.cryptoFailure,
        ),
      ],
    );

    blocTest<CreateEntryCubit, CreateEntryState>(
      'createEntry wraps unexpected errors as EntryErrorKind.unknown',
      build: () {
        when(() => repository.createEntryEncrypted(
              vaultId: any(named: 'vaultId'),
              label: any(named: 'label'),
              description: any(named: 'description'),
              icon: any(named: 'icon'),
              type: any(named: 'type'),
              payload: any(named: 'payload'),
              urlDomain: any(named: 'urlDomain'),
              privateKey: any(named: 'privateKey'),
            )).thenThrow(StateError('boom'));
        return buildCubit();
      },
      act: (cubit) => cubit.createEntry(
        vaultId: 'v-1',
        label: 'Stripe',
        type: EntryType.key,
        payload: const {'type': 'KEY', 'value': 'x'},
        privateKey: privateKey,
      ),
      expect: () => [
        isA<CreateEntryLoading>(),
        isA<CreateEntryError>().having(
          (s) => s.kind,
          'kind',
          EntryErrorKind.unknown,
        ),
      ],
    );

    blocTest<CreateEntryCubit, CreateEntryState>(
      'reset returns to Initial only when state is non-initial',
      build: () {
        when(() => repository.createEntryEncrypted(
              vaultId: any(named: 'vaultId'),
              label: any(named: 'label'),
              description: any(named: 'description'),
              icon: any(named: 'icon'),
              type: any(named: 'type'),
              payload: any(named: 'payload'),
              urlDomain: any(named: 'urlDomain'),
              privateKey: any(named: 'privateKey'),
            )).thenAnswer((_) async => fakeEntry);
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.createEntry(
          vaultId: 'v-1',
          label: 'Stripe',
          type: EntryType.key,
          payload: const {'type': 'KEY', 'value': 'x'},
          privateKey: privateKey,
        );
        cubit.reset();
        cubit.reset(); // second call is a no-op
      },
      expect: () => [
        isA<CreateEntryLoading>(),
        isA<CreateEntrySuccess>(),
        isA<CreateEntryInitial>(),
      ],
    );
  });
}
