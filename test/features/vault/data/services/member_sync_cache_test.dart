import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test(
    'old mutation cannot cross account replacement while database opens',
    () async {
      const channel = MethodChannel('test/member-cache-session');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var epoch = 0;
      messenger.setMockMethodCallHandler(channel, (_) async => ++epoch);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final source = AutoFillSourceAccessService(channel: channel);
      Future<void> begin(String principal) => source.begin(
        authority: MemberSyncSessionAuthority(
          principalId: principal,
          organizationId: 'org',
          organizationMembershipGeneration: '1',
          offlinePolicy: '24h',
          offlinePolicyVersion: 1,
        ),
        profileBinding: 'a' * 64,
        accountUnlock: {'accountId': principal},
      );
      await begin('first');
      final opening = Completer<Database>();
      final guarded = SqliteMemberSyncCache(
        databaseLoader: () => opening.future,
        captureMutationSession: source.captureSessionGuard,
        mutationGuard: source.withCiphertextMutation,
      );
      await database.insert('member_sync_profile_fence', {
        'singleton': 1,
        'generation': 9,
      });
      final clearing = guarded.clearAll();
      final rejected = expectLater(clearing, throwsStateError);
      await begin('second');
      opening.complete(database);
      await rejected;
      expect(
        (await database.query(
          'member_sync_profile_fence',
        )).single['generation'],
        9,
      );
      await guarded.clearAll();
      expect(await database.query('member_sync_profile_fence'), isEmpty);
    },
  );

  test('concurrent first readers share one database open', () async {
    final opened = Completer<Database>();
    var opens = 0;
    cache = SqliteMemberSyncCache(
      databaseLoader: () {
        opens++;
        return opened.future;
      },
    );
    final first = cache.vaultIds();
    final second = cache.state(snapshot.accessContext.vaultId);
    opened.complete(database);
    expect(await first, isEmpty);
    expect(await second, isNull);
    expect(opens, 1);
  });

  test('failed first open can be retried by a later reader', () async {
    var opens = 0;
    cache = SqliteMemberSyncCache(
      databaseLoader: () async {
        if (++opens == 1) throw StateError('synthetic open failure');
        return database;
      },
    );
    await expectLater(cache.vaultIds(), throwsStateError);
    expect(await cache.vaultIds(), isEmpty);
    expect(opens, 2);
  });

  test('synchronous loader failure does not poison later reads', () async {
    var opens = 0;
    cache = SqliteMemberSyncCache(
      databaseLoader: () {
        if (++opens == 1) throw StateError('synthetic synchronous failure');
        return Future.value(database);
      },
    );
    await expectLater(cache.vaultIds(), throwsStateError);
    expect(await cache.vaultIds(), isEmpty);
    expect(opens, 2);
  });

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
  test('native source denial completes before any canonical write', () async {
    final admitted = Completer<void>();
    final denied = Completer<void>();
    cache = SqliteMemberSyncCache(
      databaseLoader: () async => database,
      mutationGuard: <T>(Future<T> Function() write) async {
        admitted.complete();
        await denied.future;
        return write();
      },
    );
    final pending = cache.appendSnapshot(
      snapshot.accessContext.vaultId,
      snapshot.items,
    );
    await admitted.future;
    expect(await database.query('member_sync_heads'), isEmpty);
    denied.complete();
    await pending;
    expect(await database.query('member_sync_heads'), hasLength(1));
  });

  test(
    'failed native denial prevents canonical writes and reads do not deny',
    () async {
      var guards = 0;
      cache = SqliteMemberSyncCache(
        databaseLoader: () async => database,
        mutationGuard: <T>(Future<T> Function() write) async {
          guards++;
          throw StateError('synthetic durable deny failure');
        },
      );
      expect(await cache.vaultIds(), isEmpty);
      expect(await cache.state(snapshot.accessContext.vaultId), isNull);
      expect(guards, 0);
      await expectLater(
        cache.appendSnapshot(snapshot.accessContext.vaultId, snapshot.items),
        throwsStateError,
      );
      expect(await database.query('member_sync_heads'), isEmpty);
      expect(guards, 1);
    },
  );
  Future<MemberSyncCacheState> seedIndexState() async {
    await cache.promoteSnapshot(
      snapshot.accessContext.vaultId,
      sequence: '12',
      accessContext: snapshot.accessContext,
      memberVaultKey: snapshot.memberVaultKey,
      maximumObservedWallTime: snapshot.accessContext.issuedAt,
    );
    return (await cache.state(snapshot.accessContext.vaultId))!;
  }

  test('derived encrypted index roundtrips an empty sentinel', () async {
    final state = await seedIndexState();
    final index = cache;
    final id = snapshot.accessContext.vaultId;
    expect(await index.readSearchIndex(id, state), isNull);
    expect(await index.writeSearchIndex(id, state, ''), isTrue);
    expect(await index.readSearchIndex(id, state), '');
  });

  test('missing derived table stays absent after a read', () async {
    final state = await seedIndexState();
    expect(
      await cache.readSearchIndex(snapshot.accessContext.vaultId, state),
      isNull,
    );
    expect(
      await database.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE name = 'member_search_index'",
      ),
      isEmpty,
    );
  });

  for (final change in ['sequence', 'context', 'wrapper']) {
    test('derived index rejects stale $change for reads and writes', () async {
      final old = await seedIndexState();
      final id = snapshot.accessContext.vaultId;
      expect(await cache.writeSearchIndex(id, old, 'opaque-a'), isTrue);
      final context = old.accessContext.toJson();
      if (change == 'context') context['offlinePolicyVersion'] = 2;
      await cache.applyDelta(
        id,
        sequence: change == 'sequence' ? '13' : old.sequence,
        items: [],
        accessContext: MemberOfflineAccessContext.fromJson(context),
        memberVaultKey: change == 'wrapper'
            ? {...old.memberVaultKey, 'ciphertext': 'opaque-b'}
            : old.memberVaultKey,
        maximumObservedWallTime: old.maximumObservedWallTime,
      );
      expect(await cache.readSearchIndex(id, old), isNull);
      expect(await cache.writeSearchIndex(id, old, 'opaque-b'), isFalse);
      final current = (await cache.state(id))!;
      expect(await cache.readSearchIndex(id, current), isNull);
      expect(await cache.writeSearchIndex(id, current, 'opaque-c'), isTrue);
      expect(await cache.readSearchIndex(id, current), 'opaque-c');
    });
  }

  test('read-only derived cache reads but never replaces or creates', () async {
    final state = await seedIndexState();
    final id = snapshot.accessContext.vaultId;
    final reader = SqliteMemberSyncCache(
      databaseLoader: () async => database,
      readOnly: true,
    );
    expect(await reader.writeSearchIndex(id, state, 'opaque-b'), isFalse);
    expect(await reader.readSearchIndex(id, state), isNull);
    await cache.writeSearchIndex(id, state, 'opaque-a');
    expect(await reader.readSearchIndex(id, state), 'opaque-a');
    expect(await reader.writeSearchIndex(id, state, 'opaque-b'), isFalse);
    expect(await cache.readSearchIndex(id, state), 'opaque-a');
  });

  for (final cleanup in ['vault', 'all', 'quarantine', 'snapshot']) {
    test('$cleanup cleanup removes the encrypted derived index', () async {
      final state = await seedIndexState();
      final id = snapshot.accessContext.vaultId;
      await cache.writeSearchIndex(id, state, 'opaque-a');
      switch (cleanup) {
        case 'vault':
          await cache.clearVault(id);
        case 'all':
          await cache.clearAll();
        case 'snapshot':
          await cache.beginSnapshot(id, invalidateActive: true);
        case 'quarantine':
          final token = await cache.quarantineProfile();
          await expectLater(
            cache.readSearchIndex(id, state),
            throwsA(isA<MemberSyncProfileQuarantinedException>()),
          );
          await expectLater(
            cache.writeSearchIndex(id, state, 'opaque-b'),
            throwsA(isA<MemberSyncProfileQuarantinedException>()),
          );
          await cache.clearQuarantinedProfile(token);
      }
      await seedIndexState();
      expect(await cache.readSearchIndex(id, state), isNull);
    });
  }

  test(
    'derived quota failure rolls back replacement and canonical changes',
    () async {
      final state = await seedIndexState();
      final id = snapshot.accessContext.vaultId;
      await cache.writeSearchIndex(id, state, 'opaque-a');
      final bounded = SqliteMemberSyncCache(
        databaseLoader: () async => database,
        maximumProfileCacheBytes: 1,
      );
      await expectLater(
        bounded.writeSearchIndex(id, state, 'opaque-b'),
        throwsStateError,
      );
      expect(await cache.readSearchIndex(id, state), 'opaque-a');
      await expectLater(
        bounded.applyDelta(
          id,
          sequence: '13',
          items: [],
          accessContext: state.accessContext,
          memberVaultKey: state.memberVaultKey,
          maximumObservedWallTime: state.maximumObservedWallTime,
        ),
        throwsStateError,
      );
      expect(await cache.readSearchIndex(id, state), 'opaque-a');
    },
  );

  test(
    'derived writes preserve native authority while canonical writes invalidate',
    () async {
      final state = await seedIndexState();
      final id = snapshot.accessContext.vaultId;
      await cache.writeSearchIndex(id, state, 'opaque-a');
      final guarded = SqliteMemberSyncCache(
        databaseLoader: () async => database,
        mutationGuard: <T>(Future<T> Function() write) async =>
            throw StateError('synthetic denial'),
      );
      expect(await guarded.writeSearchIndex(id, state, 'opaque-b'), isTrue);
      expect(await cache.readSearchIndex(id, state), 'opaque-b');
      await expectLater(guarded.clearVault(id), throwsStateError);
    },
  );
  test('derived ciphertext bytes count toward the profile quota', () async {
    final state = await seedIndexState();
    final id = snapshot.accessContext.vaultId;
    final baseline =
        (await database.rawQuery(
              'SELECT LENGTH(applied_sequence) + LENGTH(access_context_json) + LENGTH(member_vault_key_json) + 8 AS bytes FROM member_sync_state',
            )).single['bytes']!
            as int;
    await cache.writeSearchIndex(id, state, '');
    final bindingBytes =
        (await database.rawQuery(
              'SELECT LENGTH(CAST(binding AS BLOB)) AS bytes FROM member_search_index',
            )).single['bytes']!
            as int;
    final bounded = SqliteMemberSyncCache(
      databaseLoader: () async => database,
      maximumProfileCacheBytes: baseline + bindingBytes + 100,
    );
    await expectLater(
      bounded.writeSearchIndex(id, state, 'x' * 101),
      throwsStateError,
    );
    expect(await cache.readSearchIndex(id, state), '');
  });

  test(
    'aborted derived transaction retains the previous encrypted value',
    () async {
      final state = await seedIndexState();
      final id = snapshot.accessContext.vaultId;
      await cache.writeSearchIndex(id, state, 'opaque-a');
      await database.execute(
        "CREATE TRIGGER abort_index BEFORE INSERT ON member_search_index BEGIN SELECT RAISE(ABORT, 'synthetic interruption'); END",
      );
      await expectLater(
        cache.writeSearchIndex(id, state, 'opaque-b'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await cache.readSearchIndex(id, state), 'opaque-a');
    },
  );
  test(
    'derived writer retains caller ownership while the database opens',
    () async {
      final state = await seedIndexState();
      final id = snapshot.accessContext.vaultId;
      await cache.writeSearchIndex(id, state, 'opaque-a');
      final opening = Completer<Database>();
      var session = 1;
      final guarded = SqliteMemberSyncCache(
        databaseLoader: () => opening.future,
        captureMutationSession: () {
          final captured = session;
          return () {
            if (captured != session) {
              throw StateError('synthetic session replacement');
            }
          };
        },
      );
      final pending = guarded.writeSearchIndex(id, state, 'opaque-b');
      final rejection = expectLater(pending, throwsStateError);
      session++;
      opening.complete(database);
      await rejection;
      expect(await cache.readSearchIndex(id, state), 'opaque-a');
    },
  );

  test(
    'wrapper property ordering does not invalidate an encrypted index',
    () async {
      final state = await seedIndexState();
      final id = snapshot.accessContext.vaultId;
      final reordered = MemberSyncCacheState(
        sequence: state.sequence,
        accessContext: state.accessContext,
        memberVaultKey: Map.fromEntries(
          state.memberVaultKey.entries.toList().reversed,
        ),
        maximumObservedWallTime: state.maximumObservedWallTime,
      );
      expect(await cache.writeSearchIndex(id, reordered, 'opaque-a'), isTrue);
      expect(await cache.readSearchIndex(id, state), 'opaque-a');
    },
  );
  for (final operation in ['append', 'delta', 'promote']) {
    test(
      'canonical $operation evicts derived ciphertext before enforcing quota',
      () async {
        final state = await seedIndexState();
        final id = snapshot.accessContext.vaultId;
        final canonicalBytes =
            (await database.rawQuery(
                  'SELECT LENGTH(applied_sequence) + LENGTH(access_context_json) + LENGTH(member_vault_key_json) + 8 AS bytes FROM member_sync_state',
                )).single['bytes']!
                as int;
        final itemBytes = utf8
            .encode(jsonEncode(snapshot.items.single.toJson()))
            .length;
        await cache.writeSearchIndex(id, state, 'x' * (itemBytes * 2));
        final bounded = SqliteMemberSyncCache(
          databaseLoader: () async => database,
          maximumProfileCacheBytes: canonicalBytes + itemBytes + 1,
        );
        switch (operation) {
          case 'append':
            await bounded.appendSnapshot(id, snapshot.items);
            final rows = await database.query(
              'member_sync_heads',
              where: 'generation = ?',
              whereArgs: ['staging'],
            );
            expect(rows, hasLength(1));
          case 'delta':
            await bounded.applyDelta(
              id,
              sequence: '13',
              items: snapshot.items,
              accessContext: state.accessContext,
              memberVaultKey: state.memberVaultKey,
              maximumObservedWallTime: state.maximumObservedWallTime,
            );
            expect((await cache.readHeads(id).toList()), hasLength(1));
            expect((await cache.state(id))!.sequence, '13');
          case 'promote':
            await bounded.promoteSnapshot(
              id,
              sequence: '13',
              accessContext: state.accessContext,
              memberVaultKey: state.memberVaultKey,
              maximumObservedWallTime: state.maximumObservedWallTime,
            );
            expect((await cache.state(id))!.sequence, '13');
        }
        expect(await database.query('member_search_index'), isEmpty);
        expect(
          await cache.readSearchIndex(id, (await cache.state(id))!),
          isNull,
        );
      },
    );
  }

  test('non-text derived ciphertext is a cache miss', () async {
    final state = await seedIndexState();
    final id = snapshot.accessContext.vaultId;
    await cache.writeSearchIndex(id, state, 'opaque');
    await database.rawUpdate(
      "UPDATE member_search_index SET encoded = X'0102' WHERE vault_id = ?",
      [id],
    );
    expect(await cache.readSearchIndex(id, state), isNull);
    expect((await cache.state(id))!.sequence, '12');
  });
}
