import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/member_sync_models.dart';

/// `journal_mode` returns a result row. Using `execute` for it causes
/// sqflite_darwin to surface SQLite's successful response as
/// `DatabaseException("not an error")`.
Future<void> configureMemberSyncDatabase(Database db) async {
  await db.rawQuery('PRAGMA journal_mode=WAL');
  await db.execute('PRAGMA synchronous=FULL');
}

/// Persistent sync state. Implementations may store only opaque envelopes and
/// structural cursors; decrypted labels, search terms, and keys are forbidden.
abstract interface class MemberSyncCache {
  Future<String?> sequence(String vaultId);
  Future<void> replaceSnapshot(
    String vaultId,
    String sequence,
    Stream<MemberSyncItemModel> items,
  );
  Future<void> applyDelta(
    String vaultId,
    String sequence,
    List<MemberSyncItemModel> items,
  );
  Stream<MemberSyncItemModel> readHeads(String vaultId);
  Future<void> clearVault(String vaultId);
}

/// SQLite ciphertext cache with atomic snapshot promotion and delta commits.
final class SqliteMemberSyncCache implements MemberSyncCache {
  SqliteMemberSyncCache({Future<Database> Function()? databaseLoader})
    : _databaseLoader = databaseLoader ?? _openDatabase;

  final Future<Database> Function() _databaseLoader;
  Database? _database;

  Future<Database> get _db async => _database ??= await _databaseLoader();

  static Future<Database> _openDatabase() async {
    final support = await getApplicationSupportDirectory();
    return openDatabase(
      p.join(support.path, 'vault_member_sync.db'),
      version: 1,
      onConfigure: configureMemberSyncDatabase,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE member_sync_heads (
            vault_id TEXT NOT NULL,
            entry_id TEXT NOT NULL,
            envelope_json TEXT NOT NULL,
            PRIMARY KEY (vault_id, entry_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE member_sync_state (
            vault_id TEXT PRIMARY KEY,
            applied_sequence TEXT NOT NULL
          )
        ''');
      },
    );
  }

  @override
  Future<String?> sequence(String vaultId) async {
    final rows = await (await _db).query(
      'member_sync_state',
      columns: ['applied_sequence'],
      where: 'vault_id = ?',
      whereArgs: [vaultId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['applied_sequence']! as String;
  }

  @override
  Future<void> replaceSnapshot(
    String vaultId,
    String sequence,
    Stream<MemberSyncItemModel> items,
  ) async {
    final db = await _db;
    final stagingVault = '$vaultId#staging';
    await db.delete(
      'member_sync_heads',
      where: 'vault_id = ?',
      whereArgs: [stagingVault],
    );
    try {
      await for (final item in items) {
        if (item.isTombstone) continue;
        await db.insert('member_sync_heads', {
          'vault_id': stagingVault,
          'entry_id': item.entryId,
          'envelope_json': jsonEncode(item.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await db.transaction((transaction) async {
        await transaction.delete(
          'member_sync_heads',
          where: 'vault_id = ?',
          whereArgs: [vaultId],
        );
        await transaction.rawUpdate(
          'UPDATE member_sync_heads SET vault_id = ? WHERE vault_id = ?',
          [vaultId, stagingVault],
        );
        await transaction.insert('member_sync_state', {
          'vault_id': vaultId,
          'applied_sequence': sequence,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    } catch (_) {
      await db.delete(
        'member_sync_heads',
        where: 'vault_id = ?',
        whereArgs: [stagingVault],
      );
      rethrow;
    }
  }

  @override
  Future<void> applyDelta(
    String vaultId,
    String sequence,
    List<MemberSyncItemModel> items,
  ) async {
    final db = await _db;
    await db.transaction((transaction) async {
      for (final item in items) {
        if (item.isTombstone) {
          await transaction.delete(
            'member_sync_heads',
            where: 'vault_id = ? AND entry_id = ?',
            whereArgs: [vaultId, item.entryId],
          );
        } else {
          await transaction.insert('member_sync_heads', {
            'vault_id': vaultId,
            'entry_id': item.entryId,
            'envelope_json': jsonEncode(item.toJson()),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await transaction.insert('member_sync_state', {
        'vault_id': vaultId,
        'applied_sequence': sequence,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Stream<MemberSyncItemModel> readHeads(String vaultId) async* {
    final db = await _db;
    const pageSize = 100;
    String? lastEntryId;
    while (true) {
      final rows = await db.query(
        'member_sync_heads',
        columns: ['entry_id', 'envelope_json'],
        where: lastEntryId == null
            ? 'vault_id = ?'
            : 'vault_id = ? AND entry_id > ?',
        whereArgs: lastEntryId == null ? [vaultId] : [vaultId, lastEntryId],
        orderBy: 'entry_id',
        limit: pageSize,
      );
      if (rows.isEmpty) return;
      for (final row in rows) {
        lastEntryId = row['entry_id']! as String;
        yield MemberSyncItemModel.fromJson(
          jsonDecode(row['envelope_json']! as String) as Map<String, dynamic>,
        );
      }
      if (rows.length < pageSize) return;
    }
  }

  @override
  Future<void> clearVault(String vaultId) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await transaction.delete(
        'member_sync_heads',
        where: 'vault_id IN (?, ?)',
        whereArgs: [vaultId, '$vaultId#staging'],
      );
      await transaction.delete(
        'member_sync_state',
        where: 'vault_id = ?',
        whereArgs: [vaultId],
      );
    });
  }
}
