import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/exceptions/entry_exceptions.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/edit_entry_cubit.dart';

class _MockEntryRepository extends Mock implements EntryRepository {}

class _MockCanonicalService extends Mock
    implements CanonicalEntryDetailService {}

class _MockLocalCurrentEntryService extends Mock
    implements LocalCurrentEntryService {}

void main() {
  late _MockEntryRepository repository;
  late _MockCanonicalService canonical;

  final sampleEntry = EntryEntity(
    id: 'e-1',
    vaultId: 'v-1',
    label: 'Stripe API Key',
    type: EntryType.key,
    createdAt: DateTime.utc(2026, 4, 1),
    updatedAt: DateTime.utc(2026, 4, 20),
  );
  final samplePayload = <String, dynamic>{
    'type': 'KEY',
    'value': 'sk_live_xxx',
  };
  final privateKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  CanonicalEntrySnapshot snapshot() => CanonicalEntrySnapshot(
    entry: <String, dynamic>{'currentRevision': '7'},
    payload: Map<String, dynamic>.from(samplePayload),
    secret: <String, dynamic>{'schemaVersion': 1},
  );

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(sampleEntry);
    registerFallbackValue(snapshot());
    registerFallbackValue(EntryType.key);
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    repository = _MockEntryRepository();
    canonical = _MockCanonicalService();
  });

  EditEntryCubit buildCubit() =>
      EditEntryCubit(repository: repository, canonicalService: canonical);

  group('EditEntryCubit canonical lifecycle', () {
    test(
      'starts empty until the presentation requests canonical data',
      () async {
        final cubit = buildCubit();
        expect(cubit.state, isA<EditEntryInitial>());
        verifyNever(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        );
        await cubit.close();
      },
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'explicit reveal authenticates canonical secret and emits Ready',
      build: () {
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) async => snapshot());
        return buildCubit();
      },
      act: (cubit) =>
          cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey),
      expect: () => [isA<EditEntryRevealing>(), isA<EditEntryReady>()],
      verify: (_) => verifyNever(
        () => repository.revealEntry(
          vaultId: any(named: 'vaultId'),
          entryId: any(named: 'entryId'),
          privateKey: any(named: 'privateKey'),
          wrappedVK: any(named: 'wrappedVK'),
        ),
      ),
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'corrupt canonical secret fails closed without legacy fallback',
      build: () {
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenThrow(
          const CanonicalEntryDetailException(
            CanonicalEntryDetailError.corrupt,
          ),
        );
        return buildCubit();
      },
      act: (cubit) =>
          cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey),
      expect: () => [
        isA<EditEntryRevealing>(),
        isA<EditEntryError>().having(
          (state) => state.kind,
          'kind',
          EntryErrorKind.cryptoFailure,
        ),
      ],
      verify: (_) => verifyNever(
        () => repository.revealEntry(
          vaultId: any(named: 'vaultId'),
          entryId: any(named: 'entryId'),
          privateKey: any(named: 'privateKey'),
          wrappedVK: any(named: 'wrappedVK'),
        ),
      ),
    );

    test('forced refresh bypasses a stale local head', () async {
      final local = _MockLocalCurrentEntryService();
      final current = CanonicalEntrySnapshot(
        entry: {
          'currentRevision': '9',
          'currentKeyVersion': 3,
          'updatedAt': '2026-09-01T16:00:00Z',
        },
        payload: Map<String, dynamic>.from(samplePayload),
        secret: {
          'schemaVersion': 1,
          'entryType': EntryType.key.toWire(),
          'memberLabel': 'Authoritative label',
        },
      );
      when(
        () => canonical.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => current);
      final cubit = EditEntryCubit(
        repository: repository,
        canonicalService: canonical,
        localCurrentEntry: local,
      );

      await cubit.revealForEdit(
        entry: sampleEntry,
        privateKey: privateKey,
        forceRemote: true,
      );

      final ready = cubit.state as EditEntryReady;
      expect(ready.entry.label, 'Authoritative label');
      expect(ready.entry.currentRevision, '9');
      expect(ready.entry.currentKeyVersion, 3);
      verifyNever(
        () => local.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      );
      await cubit.close();
    });

    blocTest<EditEntryCubit, EditEntryState>(
      'save creates a canonical revision and never calls legacy update',
      build: () {
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) async => snapshot());
        when(
          () => canonical.update(
            snapshot: any(named: 'snapshot'),
            expected: any(named: 'expected'),
            label: any(named: 'label'),
            description: any(named: 'description'),
            icon: any(named: 'icon'),
            type: any(named: 'type'),
            content: any(named: 'content'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer(
          (_) async => EntryEntity(
            id: sampleEntry.id,
            vaultId: sampleEntry.vaultId,
            label: 'Renamed',
            type: sampleEntry.type,
            createdAt: sampleEntry.createdAt,
            updatedAt: sampleEntry.updatedAt,
          ),
        );
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey);
        await cubit.updateEntry(
          vaultId: sampleEntry.vaultId,
          entryId: sampleEntry.id,
          label: 'Renamed',
          type: EntryType.key,
          payload: samplePayload,
          privateKey: privateKey,
          createdAt: sampleEntry.createdAt,
        );
      },
      skip: 2,
      expect: () => [isA<EditEntryLoading>(), isA<EditEntrySuccess>()],
      verify: (cubit) {
        expect(cubit.hasCanonicalSnapshot, isFalse);
        verifyNever(
          () => repository.updateEntryEncrypted(
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
            agentFields: any(named: 'agentFields'),
          ),
        );
      },
    );

    blocTest<EditEntryCubit, EditEntryState>(
      'optimistic conflict is explicit',
      build: () {
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) async => snapshot());
        when(
          () => canonical.update(
            snapshot: any(named: 'snapshot'),
            expected: any(named: 'expected'),
            label: any(named: 'label'),
            description: any(named: 'description'),
            icon: any(named: 'icon'),
            type: any(named: 'type'),
            content: any(named: 'content'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenThrow(
          const CanonicalEntryDetailException(
            CanonicalEntryDetailError.conflict,
          ),
        );
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey);
        await cubit.updateEntry(
          vaultId: sampleEntry.vaultId,
          entryId: sampleEntry.id,
          label: 'Renamed',
          type: EntryType.key,
          payload: samplePayload,
          privateKey: privateKey,
          createdAt: sampleEntry.createdAt,
        );
      },
      skip: 2,
      expect: () => [isA<EditEntryLoading>(), isA<EditEntryConflict>()],
    );

    test('coalesces repeated save taps into one canonical update', () async {
      final completion = Completer<EntryEntity>();
      when(
        () => canonical.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => snapshot());
      when(
        () => canonical.update(
          snapshot: any(named: 'snapshot'),
          expected: any(named: 'expected'),
          label: any(named: 'label'),
          description: any(named: 'description'),
          icon: any(named: 'icon'),
          type: any(named: 'type'),
          content: any(named: 'content'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) => completion.future);
      final cubit = buildCubit();
      await cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey);

      final first = cubit.updateEntry(
        vaultId: sampleEntry.vaultId,
        entryId: sampleEntry.id,
        label: 'Renamed',
        type: EntryType.key,
        payload: samplePayload,
        privateKey: privateKey,
        createdAt: sampleEntry.createdAt,
      );
      final repeated = cubit.updateEntry(
        vaultId: sampleEntry.vaultId,
        entryId: sampleEntry.id,
        label: 'Renamed',
        type: EntryType.key,
        payload: samplePayload,
        privateKey: privateKey,
        createdAt: sampleEntry.createdAt,
      );
      await repeated;
      completion.complete(
        EntryEntity(
          id: sampleEntry.id,
          vaultId: sampleEntry.vaultId,
          label: 'Renamed',
          type: sampleEntry.type,
          createdAt: sampleEntry.createdAt,
          updatedAt: sampleEntry.updatedAt,
          currentRevision: '8',
        ),
      );
      await first;

      verify(
        () => canonical.update(
          snapshot: any(named: 'snapshot'),
          expected: any(named: 'expected'),
          label: any(named: 'label'),
          description: any(named: 'description'),
          icon: any(named: 'icon'),
          type: any(named: 'type'),
          content: any(named: 'content'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).called(1);
      expect(cubit.state, isA<EditEntrySuccess>());
      await cubit.close();
    });

    test(
      'lock/background cleanup clears payload and returns initial',
      () async {
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) async => snapshot());
        final cubit = buildCubit();
        await cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey);
        final ready = cubit.state as EditEntryReady;
        cubit.clearSensitiveState();
        expect(ready.payload, isEmpty);
        expect(cubit.state, isA<EditEntryInitial>());
        await cubit.close();
      },
    );

    test(
      'late reveal completion is discarded after lifecycle cleanup',
      () async {
        final completion = Completer<CanonicalEntrySnapshot>();
        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) => completion.future);
        final cubit = buildCubit();

        final reveal = cubit.revealForEdit(
          entry: sampleEntry,
          privateKey: privateKey,
        );
        cubit.clearSensitiveState();
        final revealed = snapshot();
        completion.complete(revealed);
        await reveal;

        expect(cubit.state, isA<EditEntryInitial>());
        expect(cubit.hasCanonicalSnapshot, isFalse);
        expect(revealed.payload, isEmpty);
        expect(revealed.entry, isEmpty);
        expect(revealed.secret, isEmpty);
        await cubit.close();
      },
    );

    test('close wipes the snapshot still referenced by Ready state', () async {
      final revealed = snapshot();
      when(
        () => canonical.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => revealed);
      final cubit = buildCubit();
      await cubit.revealForEdit(entry: sampleEntry, privateKey: privateKey);
      final ready = cubit.state as EditEntryReady;

      await cubit.close();

      expect(ready.payload, isEmpty);
      expect(revealed.entry, isEmpty);
      expect(revealed.secret, isEmpty);
    });

    blocTest<EditEntryCubit, EditEntryState>(
      'delete remains repository-backed and typed',
      build: () {
        when(
          () => repository.deleteEntry(
            vaultId: any(named: 'vaultId'),
            entryId: any(named: 'entryId'),
          ),
        ).thenAnswer((_) async {});
        return buildCubit();
      },
      act: (cubit) => cubit.deleteEntry(vaultId: 'v-1', entryId: 'e-1'),
      expect: () => [isA<EditEntryLoading>(), isA<EditEntryDeleted>()],
    );
  });
}
