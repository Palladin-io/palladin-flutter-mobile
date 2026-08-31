import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_archive_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_list_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/vault_entries_tab.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Index extends Mock implements MemberIndexReader {}

class _Sync extends Mock implements MemberEntryListLoader {}

class _Restorer extends Mock implements EntryArchiveRestorer {}

class _Repository extends Mock implements EntryRepository {}

class _Auth extends Mock implements AuthBloc {}

class _TestEntryListCubit extends EntryListCubit {
  _TestEntryListCubit({required MemberEntryListLoader loader})
    : super(repository: _Repository(), vaultId: 'vault', indexLoader: loader);

  void seed() => emit(
    EntryListLoaded([
      EntryEntity(
        id: 'active',
        vaultId: 'vault',
        label: 'Active',
        type: EntryType.credential,
        createdAt: DateTime.utc(1970),
        updatedAt: DateTime.utc(1970),
      ),
    ]),
  );
}

const _archivedA = MemberIndexEntry(
  entryId: 'a',
  entryType: 0,
  memberLabel: 'Zulu Key',
  searchFields: ['local-secret-service'],
  revision: '3',
  state: MemberEntryState.archived,
);
const _archivedB = MemberIndexEntry(
  entryId: 'b',
  entryType: 1,
  memberLabel: 'Alpha Login',
  searchFields: ['example.test'],
  revision: '8',
  state: MemberEntryState.archived,
);
const _active = MemberIndexEntry(
  entryId: 'active',
  entryType: 1,
  memberLabel: 'Active',
  searchFields: [],
  revision: '2',
  state: MemberEntryState.active,
);
const _deleted = MemberIndexEntry(
  entryId: 'deleted',
  entryType: 0,
  memberLabel: 'Deleted',
  searchFields: [],
  revision: '5',
  state: MemberEntryState.deleted,
);

void main() {
  late _Index index;
  late _Sync sync;
  late _Restorer restorer;
  late Uint8List privateKey;

  setUpAll(() {
    registerFallbackValue(Uint8List(32));
    registerFallbackValue(_archivedA);
  });

  setUp(() {
    index = _Index();
    sync = _Sync();
    restorer = _Restorer();
    privateKey = Uint8List(32);
    when(
      () => index.entries('vault'),
    ).thenReturn([_active, _archivedA, _deleted, _archivedB]);
  });

  EntryArchiveCubit build({int maximumEntries = 20000}) => EntryArchiveCubit(
    vaultId: 'vault',
    index: index,
    sync: sync,
    restorer: restorer,
    maximumEntries: maximumEntries,
  );

  test('partitions Archive from Active and Deleted using local index only', () {
    final cubit = build()..loadLocal();
    final state = cubit.state as EntryArchiveLoaded;
    expect(state.entries.map((entry) => entry.entryId), ['a', 'b']);
    verify(() => index.entries('vault')).called(1);
    verifyNoMoreInteractions(index);
    cubit.close();
  });

  test('search, filter and deterministic sort stay local', () {
    final cubit = build()..loadLocal();
    cubit.search('EXAMPLE');
    expect(
      (cubit.state as EntryArchiveLoaded).visibleEntries.single.entryId,
      'b',
    );
    cubit.search('');
    cubit.filterType(0);
    expect(
      (cubit.state as EntryArchiveLoaded).visibleEntries.single.entryId,
      'a',
    );
    cubit.filterType(null);
    cubit.sortBy(EntryArchiveSort.labelAscending);
    expect(
      (cubit.state as EntryArchiveLoaded).visibleEntries.map(
        (entry) => entry.entryId,
      ),
      ['b', 'a'],
    );
    cubit.close();
  });

  blocTest<EntryArchiveCubit, EntryArchiveState>(
    'restore keeps the row pending until the subsequent delta removes it',
    build: () {
      when(
        () => restorer.restoreArchived(
          vaultId: 'vault',
          archived: _archivedA,
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => sync.load(
          vaultId: 'vault',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => [_active, _deleted, _archivedB]);
      return build()..loadLocal();
    },
    act: (cubit) => cubit.restore(entryId: 'a', memberPrivateKey: privateKey),
    expect: () => [
      isA<EntryArchiveLoaded>().having(
        (state) => state.restoringIds,
        'pending authoritative row',
        {'a'},
      ),
      isA<EntryArchiveLoaded>().having(
        (state) => state.entries.map((entry) => entry.entryId).toList(),
        'delta-reconciled archive',
        ['b'],
      ),
    ],
  );

  blocTest<EntryArchiveCubit, EntryArchiveState>(
    '409 preserves the authoritative archived row and exposes conflict',
    build: () {
      when(
        () => restorer.restoreArchived(
          vaultId: 'vault',
          archived: _archivedA,
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenThrow(
        const CanonicalEntryDetailException(CanonicalEntryDetailError.conflict),
      );
      return build()..loadLocal();
    },
    act: (cubit) => cubit.restore(entryId: 'a', memberPrivateKey: privateKey),
    expect: () => [
      isA<EntryArchiveLoaded>(),
      isA<EntryArchiveLoaded>()
          .having((state) => state.entries.length, 'rows', 2)
          .having(
            (state) => state.transientError,
            'error',
            CanonicalEntryDetailError.conflict,
          ),
    ],
    verify: (_) => verifyNever(
      () => sync.load(
        vaultId: any(named: 'vaultId'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ),
  );

  test('corrupt row cannot trigger a lifecycle request', () async {
    const corrupt = MemberIndexEntry(
      entryId: 'corrupt',
      entryType: 0,
      memberLabel: 'corrupt…record',
      searchFields: [],
      revision: '1',
      state: MemberEntryState.archived,
      corrupt: true,
    );
    when(() => index.entries('vault')).thenReturn([corrupt]);
    final cubit = build()..loadLocal();
    await cubit.restore(entryId: 'corrupt', memberPrivateKey: privateKey);
    verifyNever(
      () => restorer.restoreArchived(
        vaultId: any(named: 'vaultId'),
        archived: any(named: 'archived'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    );
    cubit.close();
  });

  test('lock wipes Archive rows and oversized indexes fail closed', () {
    final cubit = build()..loadLocal();
    cubit.lock();
    expect(cubit.state, isA<EntryArchiveLocked>());
    cubit.close();

    final bounded = build(maximumEntries: 3)..loadLocal();
    expect(bounded.state, isA<EntryArchiveError>());
    bounded.close();
  });

  test('equal labels use entry id as deterministic large-list tie-breaker', () {
    when(() => index.entries('vault')).thenReturn(
      List.generate(
        10000,
        (index) => MemberIndexEntry(
          entryId: index.toString().padLeft(4, '0'),
          entryType: index % 3,
          memberLabel: 'Same',
          searchFields: const ['bounded'],
          revision: '1',
          state: MemberEntryState.archived,
        ),
      ).reversed.toList(),
    );
    final cubit = build()..loadLocal();
    final visible = (cubit.state as EntryArchiveLoaded).visibleEntries;
    expect(visible.first.entryId, '0000');
    expect(visible.last.entryId, '9999');
    cubit.close();
  });

  testWidgets(
    'normal Entries refreshes from the current index only after Archive closes',
    (tester) async {
      final archiveClosed = Completer<void>();
      final auth = _Auth();
      final loader = _Sync();
      final entryList = _TestEntryListCubit(loader: loader)..seed();
      when(() => auth.state).thenReturn(
        AuthAuthenticated(
          userId: 'user',
          isOnboarded: true,
          isVaultLocked: false,
          privateKey: Uint8List(32),
        ),
      );
      when(
        () => auth.stream,
      ).thenAnswer((_) => const Stream<AuthState>.empty());
      when(
        () => loader.load(
          vaultId: 'vault',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => [_active]);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: auth),
            BlocProvider<EntryListCubit>.value(value: entryList),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VaultEntriesTab(
                onImport: () {},
                openArchive: (_) => archiveClosed.future,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Archive'));
      await tester.pump();
      verifyNever(
        () => loader.load(
          vaultId: any(named: 'vaultId'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      );

      archiveClosed.complete();
      await tester.pumpAndSettle();

      verify(
        () => loader.load(
          vaultId: 'vault',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).called(1);
      await entryList.close();
    },
  );
}
