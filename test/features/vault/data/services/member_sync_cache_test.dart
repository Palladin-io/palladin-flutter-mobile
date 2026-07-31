import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Database extends Mock implements Database {}

void main() {
  sqfliteFfiInit();

  test('configures WAL through the result-returning PRAGMA API', () async {
    final database = _Database();
    when(() => database.rawQuery('PRAGMA journal_mode=WAL')).thenAnswer(
      (_) async => const <Map<String, Object?>>[
        {'journal_mode': 'wal'},
      ],
    );
    when(
      () => database.execute('PRAGMA synchronous=FULL'),
    ).thenAnswer((_) async {});

    await configureMemberSyncDatabase(database);

    verify(() => database.rawQuery('PRAGMA journal_mode=WAL')).called(1);
    verify(() => database.execute('PRAGMA synchronous=FULL')).called(1);
    verifyNever(() => database.execute('PRAGMA journal_mode=WAL'));
  });

  late Database database;
  late SqliteMemberSyncCache cache;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      CREATE TABLE member_sync_heads (
        vault_id TEXT NOT NULL,
        entry_id TEXT NOT NULL,
        envelope_json TEXT NOT NULL,
        PRIMARY KEY (vault_id, entry_id)
      )
    ''');
    await database.execute('''
      CREATE TABLE member_sync_state (
        vault_id TEXT PRIMARY KEY,
        applied_sequence TEXT NOT NULL
      )
    ''');
    cache = SqliteMemberSyncCache(databaseLoader: () async => database);
  });

  tearDown(() => database.close());

  test(
    'snapshot promotion stores ciphertext only and replaces atomically',
    () async {
      await cache.replaceSnapshot(
        'vault',
        '7',
        Stream.fromIterable([_head('a')]),
      );

      expect(await cache.sequence('vault'), '7');
      expect(
        await cache.readHeads('vault').map((item) => item.entryId).toList(),
        ['a'],
      );
      final stored = await database.query('member_sync_heads');
      expect(stored.single['envelope_json'], contains('ciphertext-a'));
      expect(stored.single['envelope_json'], isNot(contains('Plain label')));

      await cache.replaceSnapshot(
        'vault',
        '9',
        Stream.fromIterable([_head('b')]),
      );
      expect(
        await cache.readHeads('vault').map((item) => item.entryId).toList(),
        ['b'],
      );
      expect(await cache.sequence('vault'), '9');
    },
  );

  test('interrupted snapshot preserves the last complete cache', () async {
    await cache.replaceSnapshot(
      'vault',
      '7',
      Stream.fromIterable([_head('a')]),
    );
    final controller = StreamController<MemberSyncItemModel>();
    final replacement = cache.replaceSnapshot('vault', '8', controller.stream);
    controller.add(_head('b'));
    controller.addError(StateError('network interrupted'));
    await controller.close();

    await expectLater(replacement, throwsStateError);
    expect(await cache.sequence('vault'), '7');
    expect(
      await cache.readHeads('vault').map((item) => item.entryId).toList(),
      ['a'],
    );
  });

  test('delta applies tombstones and sequence in one transaction', () async {
    await cache.replaceSnapshot(
      'vault',
      '7',
      Stream.fromIterable([_head('a'), _head('b')]),
    );

    await cache.applyDelta('vault', '10', [_tombstone('a'), _head('c')]);

    expect(await cache.sequence('vault'), '10');
    expect(
      await cache.readHeads('vault').map((item) => item.entryId).toList(),
      ['b', 'c'],
    );
  });
}

MemberSyncItemModel _head(String id) => MemberSyncItemModel(
  entryId: id,
  kind: 'head',
  state: 'Active',
  currentRevision: '1',
  memberIndexRevision: '1',
  currentKeyVersion: 1,
  entryKey: {'ciphertext': 'ciphertext-$id'},
  memberIndex: {'ciphertext': 'ciphertext-index-$id'},
);

MemberSyncItemModel _tombstone(String id) =>
    MemberSyncItemModel(entryId: id, kind: 'tombstone');
