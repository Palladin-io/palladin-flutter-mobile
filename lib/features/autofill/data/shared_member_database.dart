import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../vault/data/services/member_sync_cache.dart';
import 'autofill_source_access_service.dart';

/// Moves the existing ciphertext database once into the iOS App Group. SQLite
/// creates a consistent committed WAL snapshot; native owns atomic durable
/// installation under the exact quarantined source fence.
final class SharedMemberDatabase {
  SharedMemberDatabase({
    required AutoFillSourceAccessService source,
    MethodChannel? channel,
    Future<String> Function()? supportDirectory,
    DatabaseFactory? factory,
  }) : _source = source,
       _channel =
           channel ??
           const MethodChannel('io.palladin.mobile/autofill-request'),
       _supportDirectory = supportDirectory ?? _supportPath,
       _factory = factory ?? databaseFactory;
  final AutoFillSourceAccessService _source;
  final MethodChannel _channel;
  final Future<String> Function() _supportDirectory;
  final DatabaseFactory _factory;
  static Future<String> _supportPath() async =>
      (await getApplicationSupportDirectory()).path;

  Future<Database> open() async {
    final directory = await _channel.invokeMethod<String>(
      'getMemberSourceDirectory',
    );
    if (directory == null || !p.isAbsolute(directory)) {
      throw StateError('Shared Member source unavailable');
    }
    await Directory(directory).create(recursive: true);
    final target = p.join(directory, 'vault_member_sync.db');
    final legacy = p.join(await _supportDirectory(), 'vault_member_sync.db');
    if (p.equals(p.normalize(target), p.normalize(legacy))) {
      throw StateError('Shared Member source must be distinct');
    }
    if (await File(target).exists()) {
      return _openInstalled(target, legacy);
    }
    await _source.ensureSession();
    final owner = await _source.invalidate();
    final ticket = _source.ticketForMutation(owner);
    final staged = '$target.migrating';
    await _factory.deleteDatabase(staged);
    try {
      if (await File(legacy).exists()) {
        final input = await _factory.openDatabase(
          legacy,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          if (await input.getVersion() != 2) {
            throw StateError('Unsupported legacy Member source');
          }
          await input.execute('VACUUM INTO ?', [staged]);
        } finally {
          await input.close();
        }
      } else {
        final empty = await SqliteMemberSyncCache.openAt(
          staged,
          factory: _factory,
        );
        await empty.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        await empty.close();
      }
      _source.validateTicket(ticket);
      await _channel.invokeMethod<void>(
        'commitMemberSourceMigration',
        ticket.toPlatformMap(),
      );
      _source.validateTicket(ticket);
      _source.complete(owner);
      return await _openInstalled(target, legacy);
    } catch (_) {
      await _factory.deleteDatabase(staged);
      rethrow;
    }
  }

  Future<Database> _openInstalled(String target, String legacy) async {
    final database = await SqliteMemberSyncCache.openAt(
      target,
      factory: _factory,
    );
    try {
      await _factory.deleteDatabase(legacy);
      return database;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }
}
