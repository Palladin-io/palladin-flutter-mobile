import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_claw_vault/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_claw_vault/features/vault/domain/exceptions/entry_exceptions.dart';
import 'package:mobile_claw_vault/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_claw_vault/features/vault/presentation/cubit/edit_entry_cubit.dart';

class _MockEntryRepository extends Mock implements EntryRepository {}

void main() {
  late _MockEntryRepository repository;

  final sampleEntry = EntryEntity(
    id: 'e-1',
    vaultId: 'v-1',
    label: 'Stripe API Key',
    type: EntryType.key,
    urlDomain: 'stripe.com',
    createdAt: DateTime.utc(2026, 4, 1),
    updatedAt: DateTime.utc(2026, 4, 20),
  );

  final samplePayload = <String, dynamic>{
    'type': 'KEY',
    'value': 'sk_live_xxx',
  };

  final privateKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(EntryType.credential);
    registerFallbackValue(DateTime.utc(2026, 1, 1));
  });

  setUp(() {
    repository = _MockEntryRepository();
  });

  EditEntryCubit buildCubit() => EditEntryCubit(repository: repository);

  group('EditEntryCubit', () {
    test('initial state is EditEntryInitial', () {
      final cubit = buildCubit();
      expect(cubit.state, isA<EditEntryInitial>());
      cubit.close();
    });

    blocTest<EditEntryCubit, EditEntryState>(
      'setReady emits EditEntryReady with the given entry and payload',
      build: buildCubit,
      act: (cubit) => cubit.setReady(sampleEntry, samplePayload),
      expect: () => [
        isA<EditEntryReady>()
            .having((s) => s.entry.id, 'entry.id', 'e-1')
            .having((s) => s.payload['value'], "payload['value']", 'sk_live_xxx'),
      ],
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'markRevealUnavailable emits cryptoFailure error',
      build: buildCubit,
      act: (cubit) => cubit.markRevealUnavailable(),
      expect: () => [
        isA<EditEntryError>().having(
          (s) => s.kind,
          'kind',
          EntryErrorKind.cryptoFailure,
        ),
      ],
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'revealForEdit emits Revealing then Ready on success',
      build: () {
        when(() => repository.revealEntry(
              vaultId: any(named: 'vaultId'),
              entryId: any(named: 'entryId'),
              privateKey: any(named: 'privateKey'),
              wrappedVK: any(named: 'wrappedVK'),
            )).thenAnswer((_) async => RevealedEntry(
              entry: sampleEntry,
              payload: samplePayload,
            ));
        return buildCubit();
      },
      act: (cubit) => cubit.revealForEdit(
        entry: sampleEntry,
        privateKey: privateKey,
      ),
      expect: () => [
        isA<EditEntryRevealing>(),
        isA<EditEntryReady>()
            .having((s) => s.entry.id, 'entry.id', 'e-1')
            .having((s) => s.payload['value'], "payload['value']", 'sk_live_xxx'),
      ],
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'revealForEdit emits Error on EntryException',
      build: () {
        when(() => repository.revealEntry(
              vaultId: any(named: 'vaultId'),
              entryId: any(named: 'entryId'),
              privateKey: any(named: 'privateKey'),
              wrappedVK: any(named: 'wrappedVK'),
            )).thenThrow(
          const EntryException(EntryErrorKind.networkError),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.revealForEdit(
        entry: sampleEntry,
        privateKey: privateKey,
      ),
      expect: () => [
        isA<EditEntryRevealing>(),
        isA<EditEntryError>().having(
          (s) => s.kind,
          'kind',
          EntryErrorKind.networkError,
        ),
      ],
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'updateEntry forwards original createdAt to the repository',
      build: () {
        when(() => repository.updateEntryEncrypted(
              vaultId: any(named: 'vaultId'),
              entryId: any(named: 'entryId'),
              label: any(named: 'label'),
              description: any(named: 'description'),
              icon: any(named: 'icon'),
              type: any(named: 'type'),
              payload: any(named: 'payload'),
              urlDomain: any(named: 'urlDomain'),
              privateKey: any(named: 'privateKey'),
              wrappedVK: any(named: 'wrappedVK'),
              createdAt: any(named: 'createdAt'),
            )).thenAnswer((_) async => sampleEntry);
        return buildCubit();
      },
      act: (cubit) => cubit.updateEntry(
        vaultId: 'v-1',
        entryId: 'e-1',
        label: 'Renamed',
        type: EntryType.key,
        payload: samplePayload,
        privateKey: privateKey,
        createdAt: DateTime.utc(2026, 4, 1),
      ),
      expect: () => [
        isA<EditEntryLoading>(),
        isA<EditEntrySuccess>(),
      ],
      verify: (_) {
        // createdAt must be preserved end-to-end — never overwritten by now().
        verify(() => repository.updateEntryEncrypted(
              vaultId: 'v-1',
              entryId: 'e-1',
              label: 'Renamed',
              description: null,
              icon: null,
              type: EntryType.key,
              payload: samplePayload,
              urlDomain: null,
              privateKey: privateKey,
              wrappedVK: null,
              createdAt: DateTime.utc(2026, 4, 1),
            )).called(1);
      },
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'updateEntry emits Error when label is empty',
      build: buildCubit,
      act: (cubit) => cubit.updateEntry(
        vaultId: 'v-1',
        entryId: 'e-1',
        label: '   ',
        type: EntryType.key,
        payload: samplePayload,
        privateKey: privateKey,
        createdAt: DateTime.utc(2026, 4, 1),
      ),
      expect: () => [
        isA<EditEntryError>().having(
          (s) => s.kind,
          'kind',
          EntryErrorKind.unknown,
        ),
      ],
      verify: (_) {
        verifyNever(() => repository.updateEntryEncrypted(
              vaultId: any(named: 'vaultId'),
              entryId: any(named: 'entryId'),
              label: any(named: 'label'),
              type: any(named: 'type'),
              payload: any(named: 'payload'),
              privateKey: any(named: 'privateKey'),
              createdAt: any(named: 'createdAt'),
            ));
      },
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'deleteEntry emits Loading then Deleted on success',
      build: () {
        when(() => repository.deleteEntry(
              vaultId: any(named: 'vaultId'),
              entryId: any(named: 'entryId'),
            )).thenAnswer((_) async {});
        return buildCubit();
      },
      act: (cubit) => cubit.deleteEntry(vaultId: 'v-1', entryId: 'e-1'),
      expect: () => [
        isA<EditEntryLoading>(),
        isA<EditEntryDeleted>().having((s) => s.entryId, 'entryId', 'e-1'),
      ],
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'deleteEntry emits Error on EntryException',
      build: () {
        when(() => repository.deleteEntry(
              vaultId: any(named: 'vaultId'),
              entryId: any(named: 'entryId'),
            )).thenThrow(
          const EntryException(EntryErrorKind.forbidden),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.deleteEntry(vaultId: 'v-1', entryId: 'e-1'),
      expect: () => [
        isA<EditEntryLoading>(),
        isA<EditEntryError>().having(
          (s) => s.kind,
          'kind',
          EntryErrorKind.forbidden,
        ),
      ],
    );
  });
}
