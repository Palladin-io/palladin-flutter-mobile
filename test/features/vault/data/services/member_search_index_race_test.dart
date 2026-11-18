import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/datasources/member_sync_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_search_index_codec.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';

class _EntryCrypto extends Mock implements EntryV2CryptoService {}

class _VaultKeys extends Mock implements VaultRotationCryptoService {}

class _Remote extends Mock implements MemberSyncRemote {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    registerFallbackValue(Uint8List(32));
    registerFallbackValue(<String, dynamic>{});
  });

  for (final phase in ['rebuild', 'seal']) {
    test(
      'canonical advancement during $phase cannot certify old index under new sequence',
      () async {
        final fixture =
            jsonDecode(
                  File(
                    'test/fixtures/current_member_entry_sync_v2/valid-snapshot.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        final snapshot = MemberSnapshotPage.fromJson(
          Map<String, dynamic>.from(fixture['response'] as Map),
        );
        final db = await SqliteMemberSyncCache.openAt(
          inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        );
        addTearDown(db.close);
        final cache = SqliteMemberSyncCache(databaseLoader: () async => db);
        final id = snapshot.accessContext.vaultId;
        await cache.beginSnapshot(id, invalidateActive: false);
        await cache.appendSnapshot(id, snapshot.items);
        await cache.promoteSnapshot(
          id,
          sequence: '12',
          accessContext: snapshot.accessContext,
          memberVaultKey: snapshot.memberVaultKey,
          maximumObservedWallTime: snapshot.accessContext.issuedAt,
        );
        final crypto = _EntryCrypto();
        final keys = _VaultKeys();
        final entered = Completer<void>();
        final resume = Completer<void>();
        when(
          () => crypto.openEntryDek(
            entryKey: any(named: 'entryKey'),
            vaultKey: any(named: 'vaultKey'),
          ),
        ).thenAnswer((_) async => Uint8List(32));
        when(
          () => crypto.openMemberIndex(
            envelope: any(named: 'envelope'),
            vaultKey: any(named: 'vaultKey'),
          ),
        ).thenAnswer((_) async {
          if (phase == 'rebuild') {
            entered.complete();
            await resume.future;
          }
          return {
            'memberLabel': 'Synthetic',
            'entryType': 1,
            'searchFields': <String>[],
          };
        });
        when(
          () => keys.openMemberVaultKey(
            any(),
            any(),
            expectedOrganizationId: any(named: 'expectedOrganizationId'),
            expectedVaultId: any(named: 'expectedVaultId'),
            expectedVaultKeyVersion: any(named: 'expectedVaultKeyVersion'),
            expectedMemberKeyGeneration: any(
              named: 'expectedMemberKeyGeneration',
            ),
          ),
        ).thenAnswer((_) async => Uint8List(32));
        final sodium = await sodium_ffi.SodiumSumoInit.init(
          () => DynamicLibrary.open(
            Platform.environment['PALLADIN_LIBSODIUM_PATH'] ??
                '/opt/homebrew/lib/libsodium.dylib',
          ),
        );
        final service = MemberSyncService(
          remote: _Remote(),
          cache: cache,
          entryCrypto: crypto,
          vaultKeys: keys,
          searchIndexCodec: MemberSearchIndexCodec(
            sodiumLoader: () async {
              if (phase == 'seal') {
                entered.complete();
                await resume.future;
              }
              return sodium;
            },
          ),
          now: () => snapshot.accessContext.issuedAt,
        );
        addTearDown(service.lock);
        final context = snapshot.accessContext;
        final opening = service.unlockCached(
          vaultId: id,
          memberPrivateKey: Uint8List(32),
          authority: MemberSyncSessionAuthority(
            principalId: context.principalId,
            organizationId: context.organizationId,
            organizationMembershipGeneration:
                context.organizationMembershipGeneration,
            offlinePolicy: context.offlinePolicy,
            offlinePolicyVersion: context.offlinePolicyVersion,
          ),
        );
        final completed = opening.then<void>((_) {}, onError: (Object _) {});
        await entered.future;
        await cache.applyDelta(
          id,
          sequence: '13',
          items: [
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
          ],
          accessContext: context,
          memberVaultKey: snapshot.memberVaultKey,
          maximumObservedWallTime: context.issuedAt,
        );
        resume.complete();
        await completed;
        final current = await cache.state(id);
        expect(
          current?.sequence,
          '13',
          reason: 'A rebuild race must not purge newer canonical state',
        );
        expect(
          await cache.readSearchIndex(id, current!),
          isNull,
          reason: 'Old entry cannot be certified by the new sequence',
        );
        expect(service.search(''), isEmpty);
      },
    );
  }
}
