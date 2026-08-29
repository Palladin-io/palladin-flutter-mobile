import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_bridge.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_service.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_record.dart';
import 'package:mobile_palladin/features/vault/data/datasources/member_sync_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_index_preparation_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _MockVaultKeys extends Mock implements VaultRotationCryptoService {}

final class _MockAuthorityProvider extends Mock
    implements MemberSyncSessionAuthorityProvider {}

final class _MockCanonicalAdapter extends Mock
    implements CanonicalEntryDetailService {}

final class _FixtureRemote implements MemberSyncRemote {
  _FixtureRemote(this.snapshotPage);

  final MemberSnapshotPage snapshotPage;
  int snapshotRequests = 0;
  int deltaRequests = 0;

  @override
  Future<MemberSnapshotPage> snapshot({
    required String vaultId,
    String? cursor,
    int pageSize = 100,
  }) async {
    snapshotRequests += 1;
    return snapshotPage;
  }

  @override
  Future<MemberDeltaResult> delta({
    required String vaultId,
    String? afterSequence,
    String? continuationCursor,
    int pageSize = 100,
  }) async {
    deltaRequests += 1;
    return MemberDeltaSuccess(
      MemberDeltaPage(
        deltaUpperBound: snapshotPage.snapshotBaseSequence,
        appliedThroughSequence: snapshotPage.snapshotBaseSequence,
        accessContext: snapshotPage.accessContext,
        memberVaultKey: snapshotPage.memberVaultKey,
        items: const [],
      ),
    );
  }
}

final class _ForbiddenPreparation implements MemberIndexPreparer {
  int calls = 0;

  @override
  void lock() {}

  @override
  Future<List<VaultEntity>> prepare(
    Uint8List memberPrivateKey, {
    bool ensureFresh = false,
  }) async {
    calls += 1;
    throw StateError('Offline AutoFill must not start Member synchronization');
  }
}

final class _CapturingBridge implements AutoFillCacheBridge {
  AutoFillCachePayload? replacement;
  int beginCalls = 0;
  int clearCalls = 0;
  int replaceCalls = 0;

  @override
  Future<int> beginCacheSession() async {
    beginCalls += 1;
    return 77;
  }

  @override
  Future<void> clearCache({required int sessionToken}) async {
    expect(sessionToken, 77);
    clearCalls += 1;
  }

  @override
  Future<void> replaceCache(
    AutoFillCachePayload payload, {
    required int sessionToken,
  }) async {
    expect(sessionToken, 77);
    replaceCalls += 1;
    replacement = payload;
  }

  @override
  Future<int> revokeCacheAccess() async => 78;
}

Future<SodiumSumo?> _loadSodium() async {
  try {
    final configured = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    if (configured != null) {
      return await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open(configured),
      );
    }
    if (Platform.isLinux) {
      return await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open('libsodium.so'),
      );
    }
    const homebrewLibrary = '/opt/homebrew/opt/libsodium/lib/libsodium.dylib';
    if (Platform.isMacOS && File(homebrewLibrary).existsSync()) {
      return await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open(homebrewLibrary),
      );
    }
    return await SodiumSumoInit.init();
  } catch (_) {
    return null;
  }
}

Uint8List _hex(String value) => Uint8List.fromList([
  for (var offset = 0; offset < value.length; offset += 2)
    int.parse(value.substring(offset, offset + 2), radix: 16),
]);

Future<Database> _openMemberSyncDatabase(String path) =>
    databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: configureMemberSyncDatabase,
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

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    registerFallbackValue(Uint8List(32));
    registerFallbackValue(<String, dynamic>{});
  });

  test(
    'offline restart rebuilds exact native payload from persisted policy-2 material with zero HTTP',
    () async {
      final sodium = await _loadSodium();
      if (sodium == null) {
        if (Platform.environment['CI'] == 'true') {
          fail('CI requires libsodium for the offline AutoFill integration');
        }
        markTestSkipped('libsodium is unavailable in this Flutter test host');
        return;
      }

      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/current_member_entry_sync_v2/valid-snapshot.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final frozenSnapshot = MemberSnapshotPage.fromJson(
        Map<String, dynamic>.from(fixture['response'] as Map),
      );
      final frozenItem = frozenSnapshot.items.single;
      final evidence = Map<String, dynamic>.from(
        fixture['cryptoEvidence'] as Map,
      );
      final expectedSecret = Map<String, dynamic>.from(
        evidence['expectedMemberSecretPlaintext'] as Map,
      );
      final expectedIndex = Map<String, dynamic>.from(
        evidence['expectedMemberIndexPlaintext'] as Map,
      );
      final expectedContent = Map<String, dynamic>.from(
        expectedSecret['content'] as Map,
      );
      final vaultKey = _hex(evidence['expectedVaultKeyHex'] as String);
      final entryDek = _hex(evidence['expectedEntryDekHex'] as String);
      final discoveryKey = Uint8List(32)..fillRange(0, 32, 0x5a);
      final entryCrypto = EntryV2CryptoService(
        sodiumLoader: () async => sodium,
      );
      final secret = MemberSecret(
        entryType: VaultEntryType.credential,
        memberLabel: expectedIndex['memberLabel'] as String,
        agentLabel: expectedSecret['agentLabel'] as String,
        description: expectedSecret['description'] as String,
        icon: null,
        color: null,
        discoverable: true,
        content: CredentialSecretContent(
          username: expectedContent['username'] as String,
          password: expectedContent['password'] as String,
          url: 'https://fixture.invalid/login',
          urlDomain: 'fixture.invalid',
          totp: null,
          notes: null,
          customFields: const [],
        ),
        agentFieldAccess: const {
          'memberLabel': AgentFieldAccess.never,
          'agentLabel': AgentFieldAccess.discovery,
          'description': AgentFieldAccess.never,
          'icon': AgentFieldAccess.never,
          'color': AgentFieldAccess.never,
          'entryType': AgentFieldAccess.discovery,
          'credential.username': AgentFieldAccess.discovery,
          'credential.password': AgentFieldAccess.onGrantValue,
          'credential.url': AgentFieldAccess.onGrantValue,
          'credential.urlDomain': AgentFieldAccess.discovery,
          'credential.totp': AgentFieldAccess.never,
          'notes': AgentFieldAccess.onGrantValue,
        },
      );
      final bundle = await entryCrypto.seal(
        organizationId: frozenSnapshot.accessContext.organizationId,
        vaultId: frozenSnapshot.accessContext.vaultId,
        entryId: frozenItem.entryId,
        revision: int.parse(frozenItem.currentRevision!),
        entryKeyVersion: frozenItem.currentKeyVersion!,
        vaultKeyVersion: frozenSnapshot.accessContext.vaultKeyVersion,
        vdkVersion: 1,
        memberKeyGeneration: frozenSnapshot.accessContext.memberKeyGeneration,
        operation: 2,
        secret: secret,
        vaultKey: vaultKey,
        vaultDiscoveryKey: discoveryKey,
        existingEntryDek: entryDek,
      );
      final completeItem = MemberSyncItemModel.fromJson({
        ...frozenItem.toJson(),
        'entryKey': bundle.entryKey,
        'memberIndex': bundle.memberIndex,
        'memberSecret': bundle.memberSecret,
      });
      final snapshot = MemberSnapshotPage(
        snapshotBaseSequence: frozenSnapshot.snapshotBaseSequence,
        accessContext: frozenSnapshot.accessContext,
        memberVaultKey: frozenSnapshot.memberVaultKey,
        items: [completeItem],
      );
      final authority = MemberSyncSessionAuthority(
        principalId: snapshot.accessContext.principalId,
        organizationId: snapshot.accessContext.organizationId,
        organizationMembershipGeneration:
            snapshot.accessContext.organizationMembershipGeneration,
        offlinePolicy: snapshot.accessContext.offlinePolicy,
        offlinePolicyVersion: snapshot.accessContext.offlinePolicyVersion,
      );

      final directory = await Directory.systemTemp.createTemp(
        'palladin-cvt561-offline-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final databasePath = p.join(directory.path, 'member-sync.db');
      var database = await _openMemberSyncDatabase(databasePath);
      final fixtureRemote = _FixtureRemote(snapshot);
      final writer = MemberSyncService(
        remote: fixtureRemote,
        cache: SqliteMemberSyncCache(databaseLoader: () async => database),
        entryCrypto: entryCrypto,
        vaultKeys: _MockVaultKeys(),
        now: () => DateTime.utc(2026, 8, 29, 8, 30),
      );
      await writer.synchronize(
        vaultId: snapshot.accessContext.vaultId,
        vaultKey: Uint8List.fromList(vaultKey),
        minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
        authority: authority,
        authoritativeMemberVaultKey: snapshot.memberVaultKey,
      );
      expect(fixtureRemote.snapshotRequests, 1);
      expect(fixtureRemote.deltaRequests, 1);
      await database.close();

      var offlineHttpRequests = 0;
      final offlineDio = Dio(BaseOptions(baseUrl: 'https://offline.invalid'));
      offlineDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            offlineHttpRequests += 1;
            handler.reject(
              DioException.connectionError(
                requestOptions: options,
                reason: 'instrumented offline transport',
              ),
            );
          },
        ),
      );
      addTearDown(() => offlineDio.close(force: true));
      database = await _openMemberSyncDatabase(databasePath);
      addTearDown(() async {
        if (database.isOpen) await database.close();
      });
      final vaultKeys = _MockVaultKeys();
      when(
        () => vaultKeys.openMemberVaultKey(
          any(),
          any(),
          expectedOrganizationId: any(named: 'expectedOrganizationId'),
          expectedVaultId: any(named: 'expectedVaultId'),
          expectedVaultKeyVersion: any(named: 'expectedVaultKeyVersion'),
          expectedMemberKeyGeneration: any(
            named: 'expectedMemberKeyGeneration',
          ),
        ),
      ).thenAnswer((_) async => Uint8List.fromList(vaultKey));
      final restarted = MemberSyncService(
        remote: MemberSyncRemoteDatasource(offlineDio),
        cache: SqliteMemberSyncCache(databaseLoader: () async => database),
        entryCrypto: entryCrypto,
        vaultKeys: vaultKeys,
        now: () => DateTime.utc(2026, 8, 29, 8, 45),
      );
      final cachedVaultIds = await restarted.unlockAllCached(
        memberPrivateKey: Uint8List(32),
        authority: authority,
      );
      expect(cachedVaultIds, [snapshot.accessContext.vaultId]);

      final authorityProvider = _MockAuthorityProvider();
      when(authorityProvider.current).thenAnswer((_) async => authority);
      final canonicalAdapter = _MockCanonicalAdapter();
      var memberSecretDecryptions = 0;
      when(() => canonicalAdapter.adaptCanonicalSecret(any())).thenAnswer((
        invocation,
      ) {
        memberSecretDecryptions += 1;
        final opened = invocation.positionalArguments.single as Map;
        expect(opened['schema'], MemberSecret.schema);
        return Map<String, dynamic>.from(jsonDecode(jsonEncode(opened)) as Map);
      });
      final localEntries = LocalCurrentEntryService(
        reader: restarted,
        authorityProvider: authorityProvider,
        vaultKeys: vaultKeys,
        entryCrypto: entryCrypto,
        canonicalAdapter: canonicalAdapter,
      );
      final forbiddenPreparation = _ForbiddenPreparation();
      final bridge = _CapturingBridge();
      final autoFill = AutoFillCacheService(
        indexPreparation: forbiddenPreparation,
        localEntries: localEntries,
        bridge: bridge,
        memberIndex: restarted,
      );
      await autoFill.beginSession();
      await autoFill.synchronizePrepared(
        privateKey: Uint8List(32),
        vaultIds: cachedVaultIds,
      );

      expect(offlineHttpRequests, 0);
      expect(forbiddenPreparation.calls, 0);
      expect(memberSecretDecryptions, 1);
      expect(bridge.beginCalls, 1);
      expect(bridge.clearCalls, 1);
      expect(bridge.replaceCalls, 1);
      expect(bridge.replacement!.toPlatformMap(), {
        'version': 2,
        'manifest': {
          'principalId': snapshot.accessContext.principalId,
          'organizationId': snapshot.accessContext.organizationId,
          'organizationMembershipGeneration':
              snapshot.accessContext.organizationMembershipGeneration,
          'offlinePolicy': '24h',
          'offlinePolicyVersion': snapshot.accessContext.offlinePolicyVersion,
          'vaults': [
            {
              'vaultId': snapshot.accessContext.vaultId,
              'contextVersion': 1,
              'memberId': snapshot.accessContext.memberId,
              'memberKeyGeneration': snapshot.accessContext.memberKeyGeneration,
              'vaultKeyVersion': snapshot.accessContext.vaultKeyVersion,
              'memberRecipientKeyVersion':
                  snapshot.accessContext.memberRecipientKeyVersion,
              'memberRecipientKeyFingerprint':
                  snapshot.accessContext.memberRecipientKeyFingerprint,
              'issuedAt': snapshot.accessContext.issuedAt
                  .toUtc()
                  .toIso8601String(),
              'notAfter': snapshot.accessContext.notAfter
                  .toUtc()
                  .toIso8601String(),
              'entries': [
                {
                  'entryId': frozenItem.entryId,
                  'revision': frozenItem.currentRevision,
                  'keyVersion': frozenItem.currentKeyVersion,
                },
              ],
            },
          ],
        },
        'records': [
          {
            'id': frozenItem.entryId,
            'organizationId': snapshot.accessContext.organizationId,
            'vaultId': snapshot.accessContext.vaultId,
            'revision': frozenItem.currentRevision,
            'keyVersion': frozenItem.currentKeyVersion,
            'label': expectedIndex['memberLabel'],
            'username': expectedContent['username'],
            'password': expectedContent['password'],
            'domains': ['fixture.invalid'],
          },
        ],
      });

      entryDek.fillRange(0, entryDek.length, 0);
      vaultKey.fillRange(0, vaultKey.length, 0);
      discoveryKey.fillRange(0, discoveryKey.length, 0);
    },
  );
}
