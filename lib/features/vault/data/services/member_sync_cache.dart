import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/entities/vault_performance_budget.dart';
import '../models/member_sync_models.dart';
import 'member_search_index_cache.dart';

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
  Future<List<String>> vaultIds();
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

typedef MemberSyncMutationGuard =
    Future<T> Function<T>(Future<T> Function() write);

/// SQLite implementation of the policy-2 ciphertext cache.
final class SqliteMemberSyncCache
    implements MemberSyncCache, MemberSearchIndexCache {
  SqliteMemberSyncCache({
    Future<Database> Function()? databaseLoader,
    MemberSyncMutationGuard? mutationGuard,
    void Function() Function()? captureMutationSession,
    this.readOnly = false,
    this.maximumProfileCacheBytes =
        VaultPerformanceBudget.maximumMemberSyncProfileCacheBytes,
  }) : _databaseLoader = databaseLoader ?? _openDatabase,
       _mutationGuard = mutationGuard,
       _captureMutationSession = captureMutationSession;

  static const _active = 'active';
  static const _staging = 'staging';

  final Future<Database> Function() _databaseLoader;
  final MemberSyncMutationGuard? _mutationGuard;

  final void Function() Function()? _captureMutationSession;

  Future<T> _writeTransaction<T>(
    Future<T> Function(Transaction) write, {
    bool changesCanonicalState = true,
  }) async {
    // Capture caller ownership before the loader can await migration/bootstrap.
    // The native writer queue must not enclose that loader (migration uses it).
    final validate = _captureMutationSession?.call();
    final db = await _db;
    validate?.call();
    final guard = changesCanonicalState ? _mutationGuard : null;
    Future<T> commit() {
      validate?.call();
      return db.transaction((transaction) {
        validate?.call();
        return write(transaction);
      });
    }

    return guard == null ? commit() : guard(commit);
  }

  final bool readOnly;

  @override
  bool get canWriteSearchIndex => !readOnly;
  final int maximumProfileCacheBytes;
  Database? _database;
  Future<Database>? _opening;

  Future<Database> get _db {
    final database = _database;
    if (database != null) return Future.value(database);
    return _opening ??= _loadDatabase();
  }

  Future<Database> _loadDatabase() async {
    try {
      return _database = await Future<Database>.sync(_databaseLoader);
    } finally {
      _opening = null;
    }
  }

  static Future<Database> _openDatabase() async {
    final support = await getApplicationSupportDirectory();
    return openAt(p.join(support.path, 'vault_member_sync.db'));
  }

  static Future<Database> openAt(String path, {DatabaseFactory? factory}) {
    return (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
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
      ),
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

  static const _searchIndexTable = 'member_search_index';

  Future<bool> _hasSearchIndex(DatabaseExecutor db) async => (await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    [_searchIndexTable],
  )).isNotEmpty;

  String _binding(String sequence, Object? context, Object? wrapper) {
    Object? ordered(Object? value) {
      if (value is Map) {
        final keys = value.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: ordered(value[key])};
      }
      if (value is List) return value.map(ordered).toList();
      return value;
    }

    return jsonEncode(ordered([sequence, context, wrapper]));
  }

  String _expectedBinding(MemberSyncCacheState state) => _binding(
    state.sequence,
    state.accessContext.toJson(),
    state.memberVaultKey,
  );

  String _rowBinding(Map<String, Object?> row) => _binding(
    row['applied_sequence']! as String,
    jsonDecode(row['access_context_json']! as String),
    jsonDecode(row['member_vault_key_json']! as String),
  );

  @override
  Future<String?> readSearchIndex(
    String vaultId,
    MemberSyncCacheState expected,
  ) async {
    final db = await _db;
    await _requireProfileAvailable(db);
    if (!await _hasSearchIndex(db)) return null;
    // One SQLite statement observes the index, canonical authority and fence
    // together, including a quarantine committed by another process.
    final rows = await db.rawQuery(
      '''
      SELECT i.encoded, i.binding, s.applied_sequence,
             s.access_context_json, s.member_vault_key_json
      FROM member_search_index i
      JOIN member_sync_state s ON s.vault_id = i.vault_id
      WHERE i.vault_id = ? AND NOT EXISTS
        (SELECT 1 FROM member_sync_profile_fence WHERE singleton = 1)
    ''',
      [vaultId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final binding = _expectedBinding(expected);
    if (row['binding'] != binding || _rowBinding(row) != binding) return null;
    final encoded = row['encoded'];
    return encoded is String ? encoded : null;
  }

  @override
  Future<bool> writeSearchIndex(
    String vaultId,
    MemberSyncCacheState expected,
    String encoded,
  ) async {
    if (readOnly) return false;
    // This auxiliary row cannot activate native access or change canonical
    // ciphertext. Preserve session/quarantine/CAS fences without revoking the
    // native source merely to refresh a disposable encrypted projection.
    return _writeTransaction((transaction) async {
      await _requireProfileAvailable(transaction);
      final rows = await transaction.query(
        'member_sync_state',
        where: 'vault_id = ?',
        whereArgs: [vaultId],
        limit: 1,
      );
      final binding = _expectedBinding(expected);
      if (rows.isEmpty || _rowBinding(rows.single) != binding) return false;
      await transaction.execute('''
        CREATE TABLE IF NOT EXISTS member_search_index (
          vault_id TEXT PRIMARY KEY,
          binding TEXT NOT NULL,
          encoded TEXT NOT NULL
        )
      ''');
      await transaction.insert(_searchIndexTable, {
        'vault_id': vaultId,
        'binding': binding,
        'encoded': encoded,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _requireProfileWithinQuota(executor: transaction);
      return true;
    }, changesCanonicalState: false);
  }

  Future<void> _deleteSearchIndex(
    DatabaseExecutor db, [
    String? vaultId,
  ]) async {
    if (!await _hasSearchIndex(db)) return;
    await db.delete(
      _searchIndexTable,
      where: vaultId == null ? null : 'vault_id = ?',
      whereArgs: vaultId == null ? null : [vaultId],
    );
  }

  @override
  Future<int> quarantineProfile() async {
    return _writeTransaction((transaction) async {
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
    return _writeTransaction((transaction) async {
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
      await _deleteSearchIndex(transaction);
      await transaction.delete(
        'member_sync_profile_fence',
        where: 'singleton = 1 AND generation = ?',
        whereArgs: [quarantineGeneration],
      );
      return true;
    });
  }

  @override
  Future<List<String>> vaultIds() async {
    final db = await _db;
    await _requireProfileAvailable(db);
    final rows = await db.query(
      'member_sync_state',
      columns: ['vault_id'],
      orderBy: 'vault_id',
    );
    return List<String>.unmodifiable(
      rows.map((row) => row['vault_id']! as String),
    );
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
    await _writeTransaction((transaction) async {
      await _requireProfileAvailable(transaction);
      await transaction.delete(
        'member_sync_heads',
        where: 'vault_id = ? AND generation = ?',
        whereArgs: [vaultId, _staging],
      );
      if (invalidateActive) {
        await _deleteSearchIndex(transaction, vaultId);
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
    await _writeTransaction((transaction) async {
      await _requireProfileAvailable(transaction);
      await _applyItemsWith(transaction, vaultId, _staging, items);
      await _requireProfileWithinQuota(
        executor: transaction,
        evictDerived: true,
      );
    });
  }

  @override
  Future<void> applyStagedDelta(
    String vaultId,
    List<MemberSyncItemModel> items,
  ) async {
    await _writeTransaction((transaction) async {
      await _requireProfileAvailable(transaction);
      await _applyItemsWith(transaction, vaultId, _staging, items);
      await _requireProfileWithinQuota(
        executor: transaction,
        evictDerived: true,
      );
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
    await _writeTransaction((transaction) async {
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
      await _requireProfileWithinQuota(
        executor: transaction,
        evictDerived: true,
      );
    });
  }

  @override
  Future<void> discardSnapshot(String vaultId) async {
    await _writeTransaction((transaction) async {
      await _requireProfileAvailable(transaction);
      await transaction.delete(
        'member_sync_heads',
        where: 'vault_id = ? AND generation = ?',
        whereArgs: [vaultId, _staging],
      );
    });
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
    await _writeTransaction((transaction) async {
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
      await _requireProfileWithinQuota(
        executor: transaction,
        evictDerived: true,
      );
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

  Future<void> _requireProfileWithinQuota({
    DatabaseExecutor? executor,
    bool evictDerived = false,
  }) async {
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
    final canonicalBytes = rows.single['bytes']! as int;
    var bytes = canonicalBytes;
    if (await _hasSearchIndex(database)) {
      final derived = await database.rawQuery(
        'SELECT COALESCE(SUM(LENGTH(CAST(encoded AS BLOB)) + '
        'LENGTH(CAST(binding AS BLOB))), 0) AS bytes FROM member_search_index',
      );
      bytes += derived.single['bytes']! as int;
    }
    if (bytes > maximumProfileCacheBytes && evictDerived) {
      // Disposable projections must never crowd out canonical ciphertext.
      // The enclosing transaction rolls this eviction back if canonical data
      // itself exceeds the same unchanged device budget.
      await _deleteSearchIndex(database);
      bytes = canonicalBytes;
    }
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
    await _writeTransaction((transaction) async {
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
      await _deleteSearchIndex(transaction, vaultId);
    });
  }

  @override
  Future<void> clearAll() async {
    await _writeTransaction((transaction) async {
      await transaction.delete('member_sync_heads');
      await transaction.delete('member_sync_state');
      await _deleteSearchIndex(transaction);
      await transaction.delete('member_sync_profile_fence');
    });
  }
}
