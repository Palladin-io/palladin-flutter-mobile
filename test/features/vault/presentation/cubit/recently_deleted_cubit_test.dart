import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/recently_deleted_cubit.dart';

class _Remote extends Mock implements EntryRemoteDatasource {}

class _Index extends Mock implements MemberIndexReader {}

class _Sync extends Mock implements MemberEntryListLoader {}

class _Lifecycle extends Mock implements EntryArchiveRestorer {}

const _deleted = MemberIndexEntry(
  entryId: 'deleted-id',
  entryType: 1,
  memberLabel: 'Deleted Login',
  searchFields: ['local.example'],
  revision: '7',
  state: MemberEntryState.deleted,
);
const _archived = MemberIndexEntry(
  entryId: 'archived-id',
  entryType: 0,
  memberLabel: 'Archived Key',
  searchFields: [],
  revision: '2',
  state: MemberEntryState.archived,
);

void main() {
  late _Remote remote;
  late _Index index;
  late _Sync sync;
  late _Lifecycle lifecycle;

  setUpAll(() {
    registerFallbackValue(Uint8List(32));
    registerFallbackValue(_deleted);
  });

  setUp(() {
    remote = _Remote();
    index = _Index();
    sync = _Sync();
    lifecycle = _Lifecycle();
    when(() => index.entries('vault')).thenReturn([_deleted, _archived]);
    when(
      () => remote.listRecentlyDeleted(
        'vault',
        cursor: any(named: 'cursor'),
        pageSize: 100,
      ),
    ).thenAnswer(
      (_) async => {
        'items': [
          {
            'id': 'deleted-id',
            'state': 'Deleted',
            'deletedAt': '2026-07-01T00:00:00Z',
            'retentionExpiresAt': '2026-08-15T00:00:00Z',
            'memberLabel': 'HOSTILE SERVER LABEL',
            'searchFields': ['HOSTILE SERVER SEARCH'],
          },
          {
            'id': 'missing-id-1234567890',
            'state': 3,
            'deletedAt': '2026-07-02T00:00:00Z',
            'retentionExpiresAt': '2026-08-16T00:00:00Z',
          },
        ],
        'nextCursor': null,
      },
    );
  });

  RecentlyDeletedCubit build() => RecentlyDeletedCubit(
    vaultId: 'vault',
    remote: remote,
    index: index,
    sync: sync,
    lifecycle: lifecycle,
  );

  test(
    'joins structural Deleted rows with local Deleted presentation',
    () async {
      final cubit = build();
      await cubit.load();
      final state = cubit.state as RecentlyDeletedLoaded;
      expect(state.items, hasLength(2));
      expect(state.items.first.presentation, same(_deleted));
      expect(state.items.first.presentation?.memberLabel, 'Deleted Login');
      expect(state.items.last.presentation, isNull);
      expect(state.items.first.purgeAt, DateTime.utc(2026, 8, 15));
      expect(
        state.items.any((item) => item.presentation == _archived),
        isFalse,
      );
      cubit.search('HOSTILE SERVER');
      expect((cubit.state as RecentlyDeletedLoaded).visibleItems, isEmpty);
      await cubit.close();
    },
  );

  test(
    'search uses local decrypted fields and missing-row opaque id only',
    () async {
      final cubit = build();
      await cubit.load();
      clearInteractions(remote);
      cubit.search('LOCAL.EXAMPLE');
      expect(
        (cubit.state as RecentlyDeletedLoaded).visibleItems.single.entryId,
        'deleted-id',
      );
      cubit.search('123456');
      expect(
        (cubit.state as RecentlyDeletedLoaded).visibleItems.single.entryId,
        'missing-id-1234567890',
      );
      verifyNever(
        () => remote.listRecentlyDeleted(
          'vault',
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      );
      await cubit.close();
    },
  );

  test(
    'restore reconciles only after lifecycle transition and member delta',
    () async {
      when(
        () => lifecycle.restoreRecoverable(
          vaultId: 'vault',
          entry: _deleted,
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => sync.load(
          vaultId: 'vault',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => [_archived]);
      var loads = 0;
      when(
        () => remote.listRecentlyDeleted(
          'vault',
          cursor: any(named: 'cursor'),
          pageSize: 100,
        ),
      ).thenAnswer((_) async {
        loads += 1;
        return {
          'items': loads == 1
              ? [
                  {
                    'id': 'deleted-id',
                    'state': 'Deleted',
                    'deletedAt': '2026-07-01T00:00:00Z',
                    'retentionExpiresAt': '2026-08-15T00:00:00Z',
                  },
                ]
              : <Object>[],
          'nextCursor': null,
        };
      });
      final cubit = build();
      await cubit.load();
      final future = cubit.restore('deleted-id', Uint8List(32));
      expect(
        (cubit.state as RecentlyDeletedLoaded).items.single.entryId,
        'deleted-id',
      );
      await future;
      expect((cubit.state as RecentlyDeletedLoaded).items, isEmpty);
      verifyInOrder([
        () => lifecycle.restoreRecoverable(
          vaultId: 'vault',
          entry: _deleted,
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
        () => sync.load(
          vaultId: 'vault',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ]);
      await cubit.close();
    },
  );

  test(
    'missing presentation cannot restore but can purge without a key',
    () async {
      when(
        () => lifecycle.purgeDeleted(
          vaultId: 'vault',
          entryId: 'missing-id-1234567890',
        ),
      ).thenAnswer((_) async {});
      final cubit = build();
      await cubit.load();
      await cubit.restore('missing-id-1234567890', Uint8List(32));
      verifyNever(
        () => lifecycle.restoreRecoverable(
          vaultId: any(named: 'vaultId'),
          entry: any(named: 'entry'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      );
      await cubit.purge('missing-id-1234567890');
      verify(
        () => lifecycle.purgeDeleted(
          vaultId: 'vault',
          entryId: 'missing-id-1234567890',
        ),
      ).called(1);
      await cubit.close();
    },
  );

  test('lock wipes the joined plaintext presentation', () async {
    final cubit = build();
    await cubit.load();
    cubit.lock();
    expect(cubit.state, isA<RecentlyDeletedLocked>());
    await cubit.close();
  });
}
