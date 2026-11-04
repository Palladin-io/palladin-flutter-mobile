import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_palladin/features/autofill/data/shared_member_database.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const channel = MethodChannel('test/member-migration');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root, shared;
  late String legacy;
  late AutoFillSourceAccessService source;
  late bool commitFails;
  late int commits;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('member-migration-');
    shared = await Directory(p.join(root.path, 'shared')).create();
    legacy = p.join(root.path, 'vault_member_sync.db');
    commitFails = false;
    commits = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'beginSourceSession':
          return 1;
        case 'invalidateSource':
          return 2;
        case 'getMemberSourceDirectory':
          return shared.path;
        case 'commitMemberSourceMigration':
          expect((call.arguments as Map)['sourceEpoch'], 2);
          commits++;
          if (commitFails) throw PlatformException(code: 'failed');
          await File(
            p.join(shared.path, 'vault_member_sync.db.migrating'),
          ).rename(p.join(shared.path, 'vault_member_sync.db'));
          return null;
      }
      return null;
    });
    source = AutoFillSourceAccessService(channel: channel);
    await source.begin(
      authority: const MemberSyncSessionAuthority(
        principalId: 'p',
        organizationId: 'o',
        organizationMembershipGeneration: '1',
        offlinePolicy: '24h',
        offlinePolicyVersion: 1,
      ),
      profileBinding: 'a' * 64,
      accountUnlock: const {},
    );
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  test(
    'canonical migration copies committed WAL ciphertext and retires legacy only after native commit',
    () async {
      final old = await SqliteMemberSyncCache.openAt(
        legacy,
        factory: databaseFactoryFfi,
      );
      await old.insert('member_sync_profile_fence', {
        'singleton': 1,
        'generation': 42,
      });
      final loader = SharedMemberDatabase(
        source: source,
        channel: channel,
        supportDirectory: () async => root.path,
        factory: databaseFactoryFfi,
      );
      final canonical = await loader.open();
      expect(
        (await canonical.query(
          'member_sync_profile_fence',
        )).single['generation'],
        42,
      );
      expect(commits, 1);
      expect(await File(legacy).exists(), isFalse);
      await canonical.close();
      await old.close();
    },
  );
  test(
    'native commit failure keeps legacy source and cannot publish partial target',
    () async {
      final old = await SqliteMemberSyncCache.openAt(
        legacy,
        factory: databaseFactoryFfi,
      );
      await old.close();
      commitFails = true;
      final loader = SharedMemberDatabase(
        source: source,
        channel: channel,
        supportDirectory: () async => root.path,
        factory: databaseFactoryFfi,
      );
      await expectLater(loader.open(), throwsA(isA<PlatformException>()));
      expect(await File(legacy).exists(), isTrue);
      expect(
        await File(p.join(shared.path, 'vault_member_sync.db')).exists(),
        isFalse,
      );
      await expectLater(
        source.activate(expected: await source.ticket(), validateSource: () {}),
        throwsStateError,
      );
    },
  );
  test(
    'rejects a shared path alias without deleting the canonical database',
    () async {
      final existing = await SqliteMemberSyncCache.openAt(
        legacy,
        factory: databaseFactoryFfi,
      );
      await existing.close();
      shared = root;
      final loader = SharedMemberDatabase(
        source: source,
        channel: channel,
        supportDirectory: () async => root.path,
        factory: databaseFactoryFfi,
      );
      await expectLater(loader.open(), throwsStateError);
      expect(await File(legacy).exists(), isTrue);
      expect(commits, 0);
    },
  );
  test(
    'restart uses installed canonical database and retires leftover legacy',
    () async {
      final old = await SqliteMemberSyncCache.openAt(
        legacy,
        factory: databaseFactoryFfi,
      );
      await old.close();
      final target = p.join(shared.path, 'vault_member_sync.db');
      final installed = await SqliteMemberSyncCache.openAt(
        target,
        factory: databaseFactoryFfi,
      );
      await installed.insert('member_sync_profile_fence', {
        'singleton': 1,
        'generation': 77,
      });
      await installed.close();
      final loader = SharedMemberDatabase(
        source: source,
        channel: channel,
        supportDirectory: () async => root.path,
        factory: databaseFactoryFfi,
      );
      final database = await loader.open();
      expect(
        (await database.query(
          'member_sync_profile_fence',
        )).single['generation'],
        77,
      );
      expect(await File(legacy).exists(), isFalse);
      expect(commits, 0);
      await database.close();
    },
  );
}
