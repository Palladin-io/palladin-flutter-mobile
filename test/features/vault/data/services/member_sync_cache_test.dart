import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late SqliteMemberSyncCache cache;
  late MemberSnapshotPage snapshot;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/current_member_entry_sync_v2/valid-snapshot.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    snapshot = MemberSnapshotPage.fromJson(
      Map<String, dynamic>.from(fixture['response'] as Map),
    );
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE member_sync_heads (
              vault_id TEXT NOT NULL,
              generation TEXT NOT NULL,
              entry_id TEXT NOT NULL,
              envelope_json TEXT NOT NULL,
              PRIMARY KEY (vault_id, generation, entry_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE member_sync_state (
              vault_id TEXT PRIMARY KEY,
              applied_sequence TEXT NOT NULL,
              access_context_json TEXT NOT NULL,
              member_vault_key_json TEXT NOT NULL,
              maximum_observed_wall_micros INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE member_sync_profile_fence (
              singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
              generation INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    cache = SqliteMemberSyncCache(databaseLoader: () async => database);
  });

  tearDown(() => database.close());

  test('snapshot stays unreadable until closing delta promotion', () async {
    final vaultId = snapshot.accessContext.vaultId;
    await cache.beginSnapshot(vaultId, invalidateActive: false);
    await cache.appendSnapshot(vaultId, snapshot.items);

    expect(await cache.state(vaultId), isNull);
    expect(await cache.readHeads(vaultId).toList(), isEmpty);

    await cache.promoteSnapshot(
      vaultId,
      sequence: snapshot.snapshotBaseSequence,
      accessContext: snapshot.accessContext,
      memberVaultKey: snapshot.memberVaultKey,
      maximumObservedWallTime: snapshot.accessContext.issuedAt,
    );

    final state = await cache.state(vaultId);
    expect(state?.sequence, snapshot.snapshotBaseSequence);
    expect(
      state?.accessContext.principalId,
      snapshot.accessContext.principalId,
    );
    expect(
      (await cache.readHeads(vaultId).toList()).single.entryId,
      snapshot.items.single.entryId,
    );
  });

  test('closing tombstone is committed inside staged generation', () async {
    final vaultId = snapshot.accessContext.vaultId;
    await cache.beginSnapshot(vaultId, invalidateActive: false);
    await cache.appendSnapshot(vaultId, snapshot.items);
    await cache.applyStagedDelta(vaultId, [
      MemberSyncItemModel.fromJson({
        'entryId': snapshot.items.single.entryId,
        'kind': 'tombstone',
        'state': null,
        'updatedAt': null,
        'currentRevision': null,
        'memberIndexRevision': null,
        'currentKeyVersion': null,
        'entryKey': null,
        'memberIndex': null,
        'memberSecret': null,
      }),
    ]);
    await cache.promoteSnapshot(
      vaultId,
      sequence: '13',
      accessContext: snapshot.accessContext,
      memberVaultKey: snapshot.memberVaultKey,
      maximumObservedWallTime: snapshot.accessContext.issuedAt,
    );

    expect(await cache.readHeads(vaultId).toList(), isEmpty);
    expect((await cache.state(vaultId))?.sequence, '13');
  });

  test('reset invalidates active generation before replacement', () async {
    final vaultId = snapshot.accessContext.vaultId;
    await cache.beginSnapshot(vaultId, invalidateActive: false);
    await cache.appendSnapshot(vaultId, snapshot.items);
    await cache.promoteSnapshot(
      vaultId,
      sequence: '12',
      accessContext: snapshot.accessContext,
      memberVaultKey: snapshot.memberVaultKey,
      maximumObservedWallTime: snapshot.accessContext.issuedAt,
    );

    await cache.beginSnapshot(vaultId, invalidateActive: true);

    expect(await cache.state(vaultId), isNull);
    expect(await cache.readHeads(vaultId).toList(), isEmpty);
  });

  test('profile clear removes state and all ciphertext heads', () async {
    final vaultId = snapshot.accessContext.vaultId;
    await cache.beginSnapshot(vaultId, invalidateActive: false);
    await cache.appendSnapshot(vaultId, snapshot.items);
    await cache.promoteSnapshot(
      vaultId,
      sequence: '12',
      accessContext: snapshot.accessContext,
      memberVaultKey: snapshot.memberVaultKey,
      maximumObservedWallTime: snapshot.accessContext.issuedAt,
    );

    await cache.clearAll();

    expect(await cache.state(vaultId), isNull);
    expect(await cache.readHeads(vaultId).toList(), isEmpty);
  });

  test(
    'durable profile fence blocks a fresh cache instance after restart',
    () async {
      final vaultId = snapshot.accessContext.vaultId;
      await cache.beginSnapshot(vaultId, invalidateActive: false);
      await cache.appendSnapshot(vaultId, snapshot.items);
      await cache.promoteSnapshot(
        vaultId,
        sequence: '12',
        accessContext: snapshot.accessContext,
        memberVaultKey: snapshot.memberVaultKey,
        maximumObservedWallTime: snapshot.accessContext.issuedAt,
      );
      final quarantine = await cache.quarantineProfile();
      final restarted = SqliteMemberSyncCache(
        databaseLoader: () async => database,
      );

      await expectLater(
        restarted.state(vaultId),
        throwsA(isA<MemberSyncProfileQuarantinedException>()),
      );
      expect(await restarted.clearQuarantinedProfile(quarantine), isTrue);
      expect(await restarted.state(vaultId), isNull);
    },
  );

  test('stale purge token cannot clear a newer profile quarantine', () async {
    final first = await cache.quarantineProfile();
    final second = await cache.quarantineProfile();

    expect(await cache.clearQuarantinedProfile(first), isFalse);
    await expectLater(
      cache.state(snapshot.accessContext.vaultId),
      throwsA(isA<MemberSyncProfileQuarantinedException>()),
    );
    expect(await cache.clearQuarantinedProfile(second), isTrue);
  });

  test('profile quota is global and rolls back the overflowing page', () async {
    final itemBytes = utf8
        .encode(jsonEncode(snapshot.items.single.toJson()))
        .length;
    cache = SqliteMemberSyncCache(
      databaseLoader: () async => database,
      maximumProfileCacheBytes: itemBytes * 2 - 1,
    );
    final firstVault = snapshot.accessContext.vaultId;
    const secondVault = '55555555-5555-4555-8555-555555555555';
    await cache.beginSnapshot(firstVault, invalidateActive: false);
    await cache.appendSnapshot(firstVault, snapshot.items);
    await cache.promoteSnapshot(
      firstVault,
      sequence: '12',
      accessContext: snapshot.accessContext,
      memberVaultKey: snapshot.memberVaultKey,
      maximumObservedWallTime: snapshot.accessContext.issuedAt,
    );
    await cache.beginSnapshot(secondVault, invalidateActive: false);

    await expectLater(
      cache.appendSnapshot(secondVault, snapshot.items),
      throwsA(isA<StateError>()),
    );

    final stagedRows = await database.query(
      'member_sync_heads',
      where: 'vault_id = ? AND generation = ?',
      whereArgs: [secondVault, 'staging'],
    );
    expect(stagedRows, isEmpty);
    expect(await cache.readHeads(firstVault).toList(), hasLength(1));
  });
}
