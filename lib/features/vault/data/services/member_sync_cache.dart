import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/entities/vault_performance_budget.dart';
import '../models/member_sync_models.dart';

/// `journal_mode` returns a result row. Using `execute` for it causes
/// sqflite_darwin to surface SQLite's successful response as an exception.
Future<void> configureMemberSyncDatabase(Database db) async {
  await db.rawQuery('PRAGMA journal_mode=WAL');
  await db.execute('PRAGMA synchronous=FULL');
  await db.execute('PRAGMA foreign_keys=ON');
}

/// Persistent structural state for one active, complete Member stream.
final class MemberSyncCacheState {
  const MemberSyncCacheState({
    required this.sequence,
    required this.accessContext,
    required this.memberVaultKey,
    required this.maximumObservedWallTime,
  });

  final String sequence;
  final MemberOfflineAccessContext accessContext;
  final Map<String, dynamic> memberVaultKey;
  final DateTime maximumObservedWallTime;
}

/// The complete local profile is durably quarantined pending logout cleanup.
final class MemberSyncProfileQuarantinedException implements Exception {
  const MemberSyncProfileQuarantinedException();
}

/// Ciphertext-only cache. A staged snapshot is never readable until its
/// closing delta has been committed and [promoteSnapshot] swaps it atomically.
abstract interface class MemberSyncCache {
  Future<int> quarantineProfile();
  Future<bool> clearQuarantinedProfile(int quarantineGeneration);
  Future<MemberSyncCacheState?> state(String vaultId);
  Future<void> beginSnapshot(String vaultId, {required bool invalidateActive});
  Future<void> appendSnapshot(String vaultId, List<MemberSyncItemModel> items);
  Future<void> applyStagedDelta(
    String vaultId,
    List<MemberSyncItemModel> items,
  );
  Future<void> promoteSnapshot(
    String vaultId, {
    required String sequence,
    required MemberOfflineAccessContext accessContext,
    required Map<String, dynamic> memberVaultKey,
    required DateTime maximumObservedWallTime,
  });
  Future<void> discardSnapshot(String vaultId);
  Future<void> applyDelta(
    String vaultId, {
    required String sequence,
    required List<MemberSyncItemModel> items,
    required MemberOfflineAccessContext accessContext,
    required Map<String, dynamic> memberVaultKey,
    required DateTime maximumObservedWallTime,
  });
  Future<MemberSyncItemModel?> readHead(String vaultId, String entryId);
  Stream<MemberSyncItemModel> readHeads(String vaultId);
  Future<void> clearVault(String vaultId);
  Future<void> clearAll();
}

/// SQLite implementation of the policy-2 ciphertext cache.
final class SqliteMemberSyncCache implements MemberSyncCache {
  SqliteMemberSyncCache({
    Future<Database> Function()? databaseLoader,
    this.maximumProfileCacheBytes =
        VaultPerformanceBudget.maximumMemberSyncProfileCacheBytes,
  }) : _databaseLoader = databaseLoader ?? _openDatabase;

  static const _active = 'active';
  static const _staging = 'staging';

  final Future<Database> Function() _databaseLoader;
  final int maximumProfileCacheBytes;
  Database? _database;

  Future<Database> get _db async => _database ??= await _databaseLoader();

  static Future<Database> _openDatabase() async {
    final support = await getApplicationSupportDirectory();
    return openDatabase(
      p.join(support.path, 'vault_member_sync.db'),
      version: 2,
      onConfigure: configureMemberSyncDatabase,
      onCreate: (db, _) => _createSchema(db),
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          // Policy 1 never contained MemberSecret or a finite access context;
          // it cannot be upgraded into a policy-2 generation safely.
          await db.execute('DROP TABLE IF EXISTS member_sync_heads');
          await db.execute('DROP TABLE IF EXISTS member_sync_state');
          await _createSchema(db);
        }
      },
    );
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
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
  }

  @override
  Future<int> quarantineProfile() async {
    final db = await _db;
    return db.transaction((transaction) async {
      final rows = await transaction.query(
        'member_sync_profile_fence',
        columns: ['generation'],
        where: 'singleton = 1',
        limit: 1,
      );
      final generation = rows.isEmpty
          ? 1
          : (rows.single['generation']! as int) + 1;
      await transaction.insert('member_sync_profile_fence', {
        'singleton': 1,
        'generation': generation,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return generation;
    });
  }

  @override
  Future<bool> clearQuarantinedProfile(int quarantineGeneration) async {
    final db = await _db;
    return db.transaction((transaction) async {
      final rows = await transaction.query(
        'member_sync_profile_fence',
        columns: ['generation'],
        where: 'singleton = 1',
        limit: 1,
      );
      if (rows.isEmpty || rows.single['generation'] != quarantineGeneration) {
        return false;
      }
      await transaction.delete('member_sync_heads');
      await transaction.delete('member_sync_state');
      await transaction.delete(
        'member_sync_profile_fence',
        where: 'singleton = 1 AND generation = ?',
        whereArgs: [quarantineGeneration],
      );
      return true;
    });
  }

  @override
  Future<MemberSyncCacheState?> state(String vaultId) async {
    final db = await _db;
    await _requireProfileAvailable(db);
    final rows = await db.query(
      'member_sync_state',
      where: 'vault_id = ?',
      whereArgs: [vaultId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    try {
      return MemberSyncCacheState(
        sequence: row['applied_sequence']! as String,
        accessContext: MemberOfflineAccessContext.fromJson(
          jsonDecode(row['access_context_json']! as String)
              as Map<String, dynamic>,
        ),
        memberVaultKey: Map<String, dynamic>.from(
          jsonDecode(row['member_vault_key_json']! as String) as Map,
        ),
        maximumObservedWallTime: DateTime.fromMicrosecondsSinceEpoch(
          row['maximum_observed_wall_micros']! as int,
          isUtc: true,
        ),
      );
    } on Object {
      await clearVault(vaultId);
      throw const FormatException('Corrupt Member sync state');
    }
  }

  @override
  Future<void> beginSnapshot(
    String vaultId, {
    required bool invalidateActive,
  }) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await _requireProfileAvailable(transaction);
      await transaction.delete(
        'member_sync_heads',
        where: 'vault_id = ? AND generation = ?',
        whereArgs: [vaultId, _staging],
      );
      if (invalidateActive) {
        await transaction.delete(
          'member_sync_heads',
          where: 'vault_id = ? AND generation = ?',
          whereArgs: [vaultId, _active],
        );
        await transaction.delete(
          'member_sync_state',
          where: 'vault_id = ?',
          whereArgs: [vaultId],
        );
      }
    });
  }

  @override
  Future<void> appendSnapshot(
    String vaultId,
    List<MemberSyncItemModel> items,
  ) async {
    if (items.any((item) => item.isTombstone)) {
      throw const FormatException('Snapshot contains a tombstone');
    }
    final db = await _db;
    await db.transaction((transaction) async {
      await _requireProfileAvailable(transaction);
      await _applyItemsWith(transaction, vaultId, _staging, items);
      await _requireProfileWithinQuota(executor: transaction);
    });
  }

  @override
  Future<void> applyStagedDelta(
    String vaultId,
    List<MemberSyncItemModel> items,
  ) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await _requireProfileAvailable(transaction);
      await _applyItemsWith(transaction, vaultId, _staging, items);
      await _requireProfileWithinQuota(executor: transaction);
    });
  }

  @override
  Future<void> promoteSnapshot(
    String vaultId, {
    required String sequence,
    required MemberOfflineAccessContext accessContext,
    required Map<String, dynamic> memberVaultKey,
    required DateTime maximumObservedWallTime,
  }) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await _requireProfileAvailable(transaction);
      await transaction.delete(
        'member_sync_heads',
        where: 'vault_id = ? AND generation = ?',
        whereArgs: [vaultId, _active],
      );
      await transaction.rawUpdate(
        'UPDATE member_sync_heads SET generation = ? '
        'WHERE vault_id = ? AND generation = ?',
        [_active, vaultId, _staging],
      );
      await _writeState(
        transaction,
        vaultId: vaultId,
        sequence: sequence,
        accessContext: accessContext,
        memberVaultKey: memberVaultKey,
        maximumObservedWallTime: maximumObservedWallTime,
      );
      await _requireProfileWithinQuota(executor: transaction);
    });
  }

  @override
  Future<void> discardSnapshot(String vaultId) async {
    final db = await _db;
    await _requireProfileAvailable(db);
    await db.delete(
      'member_sync_heads',
      where: 'vault_id = ? AND generation = ?',
      whereArgs: [vaultId, _staging],
    );
  }

  @override
  Future<void> applyDelta(
    String vaultId, {
    required String sequence,
    required List<MemberSyncItemModel> items,
    required MemberOfflineAccessContext accessContext,
    required Map<String, dynamic> memberVaultKey,
    required DateTime maximumObservedWallTime,
  }) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await _requireProfileAvailable(transaction);
      final current = await transaction.query(
        'member_sync_state',
        columns: ['applied_sequence'],
        where: 'vault_id = ?',
        whereArgs: [vaultId],
        limit: 1,
      );
      if (current.isEmpty ||
          BigInt.parse(sequence) <
              BigInt.parse(current.single['applied_sequence']! as String)) {
        throw const FormatException('Non-monotonic local Member delta');
      }
      await _applyItemsWith(transaction, vaultId, _active, items);
      await _writeState(
        transaction,
        vaultId: vaultId,
        sequence: sequence,
        accessContext: accessContext,
        memberVaultKey: memberVaultKey,
        maximumObservedWallTime: maximumObservedWallTime,
      );
      await _requireProfileWithinQuota(executor: transaction);
    });
  }

  @override
  Future<MemberSyncItemModel?> readHead(String vaultId, String entryId) async {
    final db = await _db;
    await _requireProfileAvailable(db);
    final rows = await db.query(
      'member_sync_heads',
      columns: ['envelope_json'],
      where: 'vault_id = ? AND generation = ? AND entry_id = ?',
      whereArgs: [vaultId, _active, entryId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _decodeHead(rows.single['envelope_json']! as String);
  }

  @override
  Stream<MemberSyncItemModel> readHeads(String vaultId) async* {
    final db = await _db;
    const pageSize = 100;
    String? lastEntryId;
    while (true) {
      await _requireProfileAvailable(db);
      final rows = await db.query(
        'member_sync_heads',
        columns: ['entry_id', 'envelope_json'],
        where: lastEntryId == null
            ? 'vault_id = ? AND generation = ?'
            : 'vault_id = ? AND generation = ? AND entry_id > ?',
        whereArgs: lastEntryId == null
            ? [vaultId, _active]
            : [vaultId, _active, lastEntryId],
        orderBy: 'entry_id',
        limit: pageSize,
      );
      if (rows.isEmpty) return;
      for (final row in rows) {
        lastEntryId = row['entry_id']! as String;
        yield _decodeHead(row['envelope_json']! as String);
      }
      if (rows.length < pageSize) return;
    }
  }

  MemberSyncItemModel _decodeHead(String encoded) {
    final value = jsonDecode(encoded);
    if (value is! Map) throw const FormatException('Corrupt Member head');
    final item = MemberSyncItemModel.fromJson(Map<String, dynamic>.from(value));
    if (item.isTombstone) {
      throw const FormatException('Persisted tombstone is not a head');
    }
    return item;
  }

  Future<void> _applyItemsWith(
    DatabaseExecutor executor,
    String vaultId,
    String generation,
    List<MemberSyncItemModel> items,
  ) async {
    for (final item in items) {
      if (item.isTombstone) {
        await executor.delete(
          'member_sync_heads',
          where: 'vault_id = ? AND generation = ? AND entry_id = ?',
          whereArgs: [vaultId, generation, item.entryId],
        );
      } else {
        await executor.insert('member_sync_heads', {
          'vault_id': vaultId,
          'generation': generation,
          'entry_id': item.entryId,
          'envelope_json': jsonEncode(item.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  Future<void> _writeState(
    DatabaseExecutor executor, {
    required String vaultId,
    required String sequence,
    required MemberOfflineAccessContext accessContext,
    required Map<String, dynamic> memberVaultKey,
    required DateTime maximumObservedWallTime,
  }) => executor.insert('member_sync_state', {
    'vault_id': vaultId,
    'applied_sequence': sequence,
    'access_context_json': jsonEncode(accessContext.toJson()),
    'member_vault_key_json': jsonEncode(memberVaultKey),
    'maximum_observed_wall_micros': maximumObservedWallTime
        .toUtc()
        .microsecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> _requireProfileWithinQuota({DatabaseExecutor? executor}) async {
    final database = executor ?? await _db;
    final rows = await database.rawQuery('''
      SELECT
        (SELECT COALESCE(SUM(LENGTH(envelope_json)), 0)
           FROM member_sync_heads) +
        (SELECT COALESCE(SUM(
           LENGTH(applied_sequence) +
           LENGTH(access_context_json) +
           LENGTH(member_vault_key_json) + 8
         ), 0) FROM member_sync_state) AS bytes
      ''');
    final bytes = rows.single['bytes']! as int;
    if (bytes > maximumProfileCacheBytes) {
      throw StateError('Member sync cache exceeds the profile quota');
    }
  }

  Future<void> _requireProfileAvailable(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'member_sync_profile_fence',
      columns: ['generation'],
      where: 'singleton = 1',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw const MemberSyncProfileQuarantinedException();
    }
  }

  @override
  Future<void> clearVault(String vaultId) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await _requireProfileAvailable(transaction);
      await transaction.delete(
        'member_sync_heads',
        where: 'vault_id = ?',
        whereArgs: [vaultId],
      );
      await transaction.delete(
        'member_sync_state',
        where: 'vault_id = ?',
        whereArgs: [vaultId],
      );
    });
  }

  @override
  Future<void> clearAll() async {
    final db = await _db;
    await db.transaction((transaction) async {
      await transaction.delete('member_sync_heads');
      await transaction.delete('member_sync_state');
      await transaction.delete('member_sync_profile_fence');
    });
  }
}
