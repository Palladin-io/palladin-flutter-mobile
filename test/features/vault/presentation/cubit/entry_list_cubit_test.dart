import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_claw_vault/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_claw_vault/features/vault/domain/exceptions/entry_exceptions.dart';
import 'package:mobile_claw_vault/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_claw_vault/features/vault/presentation/cubit/entry_list_cubit.dart';

class _MockEntryRepository extends Mock implements EntryRepository {}

void main() {
  late _MockEntryRepository repository;

  final sampleEntries = <EntryEntity>[
    EntryEntity(
      id: 'e-1',
      vaultId: 'v-1',
      label: 'Stripe API Key',
      type: EntryType.key,
      urlDomain: 'stripe.com',
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 20),
    ),
    EntryEntity(
      id: 'e-2',
      vaultId: 'v-1',
      label: 'GitHub Login',
      type: EntryType.credential,
      urlDomain: 'github.com',
      createdAt: DateTime.utc(2026, 3, 15),
      updatedAt: DateTime.utc(2026, 4, 10),
    ),
  ];

  final privateKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(EntryType.credential);
  });

  setUp(() {
    repository = _MockEntryRepository();
  });

  EntryListCubit buildCubit() => EntryListCubit(
        repository: repository,
        vaultId: 'v-1',
      );

  group('EntryListCubit', () {
    test('initial state is EntryListInitial', () {
      final cubit = buildCubit();
      expect(cubit.state, isA<EntryListInitial>());
      cubit.close();
    });

    blocTest<EntryListCubit, EntryListState>(
      'loadEntries emits Loading then Loaded on success',
      build: () {
        when(() => repository.listEntries(any()))
            .thenAnswer((_) async => sampleEntries);
        return buildCubit();
      },
      act: (cubit) => cubit.loadEntries(),
      expect: () => [
        isA<EntryListLoading>(),
        isA<EntryListLoaded>().having(
          (s) => s.entries.length,
          'entries.length',
          2,
        ),
      ],
      verify: (_) {
        verify(() => repository.listEntries('v-1')).called(1);
      },
    );

    blocTest<EntryListCubit, EntryListState>(
      'loadEntries emits Loading then Loaded(empty) when no entries',
      build: () {
        when(() => repository.listEntries(any()))
            .thenAnswer((_) async => const <EntryEntity>[]);
        return buildCubit();
      },
      act: (cubit) => cubit.loadEntries(),
      expect: () => [
        isA<EntryListLoading>(),
        isA<EntryListLoaded>().having((s) => s.entries, 'entries', isEmpty),
      ],
    );

    blocTest<EntryListCubit, EntryListState>(
      'loadEntries emits Error on EntryException',
      build: () {
        when(() => repository.listEntries(any()))
            .thenThrow(const EntryException(EntryErrorKind.networkError));
        return buildCubit();
      },
      act: (cubit) => cubit.loadEntries(),
      expect: () => [
        isA<EntryListLoading>(),
        isA<EntryListError>().having(
          (s) => s.kind,
          'kind',
          EntryErrorKind.networkError,
        ),
      ],
    );

    blocTest<EntryListCubit, EntryListState>(
      'loadEntries wraps unexpected errors as EntryErrorKind.unknown',
      build: () {
        when(() => repository.listEntries(any()))
            .thenThrow(StateError('boom'));
        return buildCubit();
      },
      act: (cubit) => cubit.loadEntries(),
      expect: () => [
        isA<EntryListLoading>(),
        isA<EntryListError>().having(
          (s) => s.kind,
          'kind',
          EntryErrorKind.unknown,
        ),
      ],
    );

    blocTest<EntryListCubit, EntryListState>(
      'revealEntry decrypts and stashes the payload on Loaded state',
      build: () {
        when(() => repository.listEntries(any()))
            .thenAnswer((_) async => sampleEntries);
        when(() => repository.revealEntry(
              vaultId: any(named: 'vaultId'),
              entryId: any(named: 'entryId'),
              privateKey: any(named: 'privateKey'),
            )).thenAnswer((_) async => RevealedEntry(
              entry: sampleEntries.first,
              payload: const {'type': 'KEY', 'value': 'sk_live_xxx'},
            ));
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.loadEntries();
        await cubit.revealEntry(entryId: 'e-1', privateKey: privateKey);
      },
      expect: () => [
        isA<EntryListLoading>(),
        isA<EntryListLoaded>(),
        isA<EntryListLoaded>().having(
          (s) => s.revealedEntries['e-1']?['value'],
          "revealedEntries['e-1'].value",
          'sk_live_xxx',
        ),
      ],
    );

    blocTest<EntryListCubit, EntryListState>(
      'revealEntry skips when already revealed (no second emit)',
      build: () {
        when(() => repository.listEntries(any()))
            .thenAnswer((_) async => sampleEntries);
        when(() => repository.revealEntry(
              vaultId: any(named: 'vaultId'),
              entryId: any(named: 'entryId'),
              privateKey: any(named: 'privateKey'),
            )).thenAnswer((_) async => RevealedEntry(
              entry: sampleEntries.first,
              payload: const {'type': 'KEY', 'value': 'x'},
            ));
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.loadEntries();
        await cubit.revealEntry(entryId: 'e-1', privateKey: privateKey);
        await cubit.revealEntry(entryId: 'e-1', privateKey: privateKey);
      },
      verify: (_) {
        // Repository was hit exactly once even though we called reveal twice.
        verify(() => repository.revealEntry(
              vaultId: any(named: 'vaultId'),
              entryId: 'e-1',
              privateKey: any(named: 'privateKey'),
            )).called(1);
      },
    );

    blocTest<EntryListCubit, EntryListState>(
      'hideEntry drops a previously-revealed payload',
      build: () {
        when(() => repository.listEntries(any()))
            .thenAnswer((_) async => sampleEntries);
        when(() => repository.revealEntry(
              vaultId: any(named: 'vaultId'),
              entryId: any(named: 'entryId'),
              privateKey: any(named: 'privateKey'),
            )).thenAnswer((_) async => RevealedEntry(
              entry: sampleEntries.first,
              payload: const {'type': 'KEY', 'value': 'sk_live_xxx'},
            ));
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.loadEntries();
        await cubit.revealEntry(entryId: 'e-1', privateKey: privateKey);
        cubit.hideEntry('e-1');
      },
      // Last emitted state has no revealed entries.
      verify: (cubit) {
        final state = cubit.state;
        expect(state, isA<EntryListLoaded>());
        expect((state as EntryListLoaded).revealedEntries, isEmpty);
      },
    );

    blocTest<EntryListCubit, EntryListState>(
      'deleteEntry removes via repo then refreshes the list',
      build: () {
        when(() => repository.deleteEntry(
              vaultId: any(named: 'vaultId'),
              entryId: any(named: 'entryId'),
            )).thenAnswer((_) async {});
        when(() => repository.listEntries(any()))
            .thenAnswer((_) async => sampleEntries.skip(1).toList());
        return buildCubit();
      },
      act: (cubit) => cubit.deleteEntry('e-1'),
      expect: () => [
        isA<EntryListLoading>(),
        isA<EntryListLoaded>().having(
          (s) => s.entries.single.id,
          'entries.single.id',
          'e-2',
        ),
      ],
      verify: (_) {
        verify(() => repository.deleteEntry(
              vaultId: 'v-1',
              entryId: 'e-1',
            )).called(1);
      },
    );

    blocTest<EntryListCubit, EntryListState>(
      'appendEntry inserts a fresh entry at the head of the loaded list',
      build: () {
        when(() => repository.listEntries(any()))
            .thenAnswer((_) async => sampleEntries);
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.loadEntries();
        await cubit.appendEntry(EntryEntity(
          id: 'e-new',
          vaultId: 'v-1',
          label: 'Fresh',
          type: EntryType.credential,
          createdAt: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 5, 1),
        ));
      },
      verify: (cubit) {
        final state = cubit.state;
        expect(state, isA<EntryListLoaded>());
        expect((state as EntryListLoaded).entries.first.id, 'e-new');
        expect(state.entries.length, 3);
      },
    );
  });
}
