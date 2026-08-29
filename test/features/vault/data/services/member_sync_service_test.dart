import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/member_sync_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';

class _MockEntryCrypto extends Mock implements EntryV2CryptoService {}

class _MockVaultKeys extends Mock implements VaultRotationCryptoService {}

final class _FakeRemote implements MemberSyncRemote {
  late MemberSnapshotPage snapshotPage;
  late MemberDeltaResult deltaResult;
  int snapshotRequests = 0;
  int deltaRequests = 0;
  Completer<MemberDeltaResult>? deltaCompleter;

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
    final pending = deltaCompleter;
    if (pending != null) return pending.future;
    return deltaResult;
  }
}

final class _MemoryCache implements MemberSyncCache {
  final Map<String, MemberSyncCacheState> states = {};
  final Map<String, Map<String, MemberSyncItemModel>> active = {};
  final Map<String, Map<String, MemberSyncItemModel>> staged = {};
  bool failClearVault = false;
  bool failClearAll = false;

  @override
  Future<MemberSyncCacheState?> state(String vaultId) async => states[vaultId];

  @override
  Future<void> beginSnapshot(
    String vaultId, {
    required bool invalidateActive,
  }) async {
    staged[vaultId] = {};
    if (invalidateActive) {
      active.remove(vaultId);
      states.remove(vaultId);
    }
  }

  @override
  Future<void> appendSnapshot(
    String vaultId,
    List<MemberSyncItemModel> items,
  ) => _apply(staged.putIfAbsent(vaultId, () => {}), items);

  @override
  Future<void> applyStagedDelta(
    String vaultId,
    List<MemberSyncItemModel> items,
  ) => _apply(staged.putIfAbsent(vaultId, () => {}), items);

  @override
  Future<void> promoteSnapshot(
    String vaultId, {
    required String sequence,
    required MemberOfflineAccessContext accessContext,
    required Map<String, dynamic> memberVaultKey,
    required DateTime maximumObservedWallTime,
  }) async {
    active[vaultId] = Map.of(staged.remove(vaultId) ?? {});
    states[vaultId] = MemberSyncCacheState(
      sequence: sequence,
      accessContext: accessContext,
      memberVaultKey: memberVaultKey,
      maximumObservedWallTime: maximumObservedWallTime,
    );
  }

  @override
  Future<void> discardSnapshot(String vaultId) async {
    staged.remove(vaultId);
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
    await _apply(active.putIfAbsent(vaultId, () => {}), items);
    states[vaultId] = MemberSyncCacheState(
      sequence: sequence,
      accessContext: accessContext,
      memberVaultKey: memberVaultKey,
      maximumObservedWallTime: maximumObservedWallTime,
    );
  }

  Future<void> _apply(
    Map<String, MemberSyncItemModel> target,
    List<MemberSyncItemModel> items,
  ) async {
    for (final item in items) {
      if (item.isTombstone) {
        target.remove(item.entryId);
      } else {
        target[item.entryId] = item;
      }
    }
  }

  @override
  Future<MemberSyncItemModel?> readHead(String vaultId, String entryId) async =>
      active[vaultId]?[entryId];

  @override
  Stream<MemberSyncItemModel> readHeads(String vaultId) =>
      Stream.fromIterable(active[vaultId]?.values ?? const []);

  @override
  Future<void> clearVault(String vaultId) async {
    if (failClearVault) throw StateError('simulated storage failure');
    states.remove(vaultId);
    active.remove(vaultId);
    staged.remove(vaultId);
  }

  @override
  Future<void> clearAll() async {
    if (failClearAll) throw StateError('simulated profile cleanup failure');
    states.clear();
    active.clear();
    staged.clear();
  }
}

void main() {
  late MemberSnapshotPage snapshot;
  late _FakeRemote remote;
  late _MemoryCache cache;
  late _MockEntryCrypto entryCrypto;
  late _MockVaultKeys vaultKeys;
  late MemberSyncService service;
  late MemberSyncSessionAuthority authority;
  var now = DateTime.utc(2026, 8, 29, 8, 30);

  setUpAll(() {
    registerFallbackValue(Uint8List(32));
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    now = DateTime.utc(2026, 8, 29, 8, 30);
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
    authority = MemberSyncSessionAuthority(
      principalId: snapshot.accessContext.principalId,
      organizationId: snapshot.accessContext.organizationId,
      organizationMembershipGeneration:
          snapshot.accessContext.organizationMembershipGeneration,
      offlinePolicy: snapshot.accessContext.offlinePolicy,
      offlinePolicyVersion: snapshot.accessContext.offlinePolicyVersion,
    );
    remote = _FakeRemote()..snapshotPage = snapshot;
    remote.deltaResult = MemberDeltaSuccess(
      MemberDeltaPage.fromJson({
        'deltaUpperBound': snapshot.snapshotBaseSequence,
        'appliedThroughSequence': snapshot.snapshotBaseSequence,
        'accessContext': snapshot.accessContext.toJson(),
        'memberVaultKey': snapshot.memberVaultKey,
        'items': <Object?>[],
        'continuationCursor': null,
      }),
    );
    cache = _MemoryCache();
    entryCrypto = _MockEntryCrypto();
    vaultKeys = _MockVaultKeys();
    when(
      () => entryCrypto.openEntryDek(
        entryKey: any(named: 'entryKey'),
        vaultKey: any(named: 'vaultKey'),
      ),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => entryCrypto.openMemberIndex(
        envelope: any(named: 'envelope'),
        vaultKey: any(named: 'vaultKey'),
      ),
    ).thenAnswer(
      (_) async => {
        'memberLabel': 'Offline credential',
        'entryType': 1,
        'searchFields': ['offline'],
      },
    );
    service = MemberSyncService(
      remote: remote,
      cache: cache,
      entryCrypto: entryCrypto,
      vaultKeys: vaultKeys,
      now: () => now,
    );
  });

  test('initial synchronization is snapshot plus one closing delta', () async {
    final durable = expectLater(
      service.durableUpdates,
      emits(snapshot.accessContext.vaultId),
    );

    final result = await service.synchronize(
      vaultId: snapshot.accessContext.vaultId,
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
      authority: authority,
      authoritativeMemberVaultKey: snapshot.memberVaultKey,
    );

    expect(remote.snapshotRequests, 1);
    expect(remote.deltaRequests, 1);
    expect(result.usedSnapshot, isTrue);
    expect(result.entryCount, 1);
    expect(cache.states, hasLength(1));
    await durable;
  });

  test('public local reader returns one complete ciphertext item', () async {
    await service.synchronize(
      vaultId: snapshot.accessContext.vaultId,
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
      authority: authority,
      authoritativeMemberVaultKey: snapshot.memberVaultKey,
    );

    final material = await service.readCurrent(
      vaultId: snapshot.accessContext.vaultId,
      entryId: snapshot.items.single.entryId,
      authority: authority,
    );

    expect(material?.item.memberIndex, isNotNull);
    expect(material?.item.memberSecret, isNotNull);
    expect(material?.item.entryKey, isNotNull);
    expect(material?.accessContext.notAfter, snapshot.accessContext.notAfter);
  });

  test('offline unlock reopens a complete persisted generation', () async {
    await service.synchronize(
      vaultId: snapshot.accessContext.vaultId,
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
      authority: authority,
      authoritativeMemberVaultKey: snapshot.memberVaultKey,
    );
    service.lock();
    when(
      () => vaultKeys.openMemberVaultKey(
        any(),
        any(),
        expectedOrganizationId: any(named: 'expectedOrganizationId'),
        expectedVaultId: any(named: 'expectedVaultId'),
        expectedVaultKeyVersion: any(named: 'expectedVaultKeyVersion'),
        expectedMemberKeyGeneration: any(named: 'expectedMemberKeyGeneration'),
      ),
    ).thenAnswer((_) async => Uint8List(32));

    await service.unlockCached(
      vaultId: snapshot.accessContext.vaultId,
      memberPrivateKey: Uint8List(32),
      authority: authority,
    );

    expect(service.entries(snapshot.accessContext.vaultId), hasLength(1));
    expect(remote.snapshotRequests, 1);
    expect(remote.deltaRequests, 1);
  });

  test('corrupt MemberSecret binding rejects whole generation', () async {
    final itemJson = snapshot.items.single.toJson();
    final secret = Map<String, dynamic>.from(itemJson['memberSecret'] as Map);
    final descriptor = Map<String, dynamic>.from(secret['descriptor'] as Map);
    secret['descriptor'] = {...descriptor, 'resourceRevision': '999'};
    itemJson['memberSecret'] = secret;
    remote.snapshotPage = MemberSnapshotPage(
      snapshotBaseSequence: snapshot.snapshotBaseSequence,
      accessContext: snapshot.accessContext,
      memberVaultKey: snapshot.memberVaultKey,
      items: [MemberSyncItemModel.fromJson(itemJson)],
    );

    await expectLater(
      service.synchronize(
        vaultId: snapshot.accessContext.vaultId,
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
        authority: authority,
        authoritativeMemberVaultKey: snapshot.memberVaultKey,
      ),
      throwsFormatException,
    );
    expect(cache.states, isEmpty);
    expect(cache.active, isEmpty);
  });

  test('stale EntryKey resource revision rejects whole generation', () async {
    final itemJson = snapshot.items.single.toJson();
    final entryKey = Map<String, dynamic>.from(itemJson['entryKey'] as Map);
    final descriptor = Map<String, dynamic>.from(entryKey['descriptor'] as Map);
    entryKey['descriptor'] = {...descriptor, 'resourceRevision': '11'};
    itemJson['entryKey'] = entryKey;
    remote.snapshotPage = MemberSnapshotPage(
      snapshotBaseSequence: snapshot.snapshotBaseSequence,
      accessContext: snapshot.accessContext,
      memberVaultKey: snapshot.memberVaultKey,
      items: [MemberSyncItemModel.fromJson(itemJson)],
    );

    await expectLater(
      service.synchronize(
        vaultId: snapshot.accessContext.vaultId,
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
        authority: authority,
        authoritativeMemberVaultKey: snapshot.memberVaultKey,
      ),
      throwsFormatException,
    );
    expect(cache.states, isEmpty);
  });

  test('misbound EntryKey wrapping Vault-key version is rejected', () async {
    final itemJson = snapshot.items.single.toJson();
    final entryKey = Map<String, dynamic>.from(itemJson['entryKey'] as Map);
    final descriptor = Map<String, dynamic>.from(entryKey['descriptor'] as Map);
    entryKey['descriptor'] = {
      ...descriptor,
      'binding': {'wrappingVaultKeyVersion': 2},
    };
    itemJson['entryKey'] = entryKey;
    remote.snapshotPage = MemberSnapshotPage(
      snapshotBaseSequence: snapshot.snapshotBaseSequence,
      accessContext: snapshot.accessContext,
      memberVaultKey: snapshot.memberVaultKey,
      items: [MemberSyncItemModel.fromJson(itemJson)],
    );

    await expectLater(
      service.synchronize(
        vaultId: snapshot.accessContext.vaultId,
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
        authority: authority,
        authoritativeMemberVaultKey: snapshot.memberVaultKey,
      ),
      throwsFormatException,
    );
    expect(cache.states, isEmpty);
  });

  test('offline policy is bound to the authenticated token claims', () async {
    final wrongAuthority = MemberSyncSessionAuthority(
      principalId: authority.principalId,
      organizationId: authority.organizationId,
      organizationMembershipGeneration:
          authority.organizationMembershipGeneration,
      offlinePolicy: '4h',
      offlinePolicyVersion: authority.offlinePolicyVersion,
    );

    await expectLater(
      service.synchronize(
        vaultId: snapshot.accessContext.vaultId,
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
        authority: wrongAuthority,
        authoritativeMemberVaultKey: snapshot.memberVaultKey,
      ),
      throwsFormatException,
    );
    expect(cache.states, isEmpty);
  });

  test('expired cached authority purges instead of revealing', () async {
    await service.synchronize(
      vaultId: snapshot.accessContext.vaultId,
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
      authority: authority,
      authoritativeMemberVaultKey: snapshot.memberVaultKey,
    );
    now = snapshot.accessContext.notAfter.add(const Duration(seconds: 1));

    await expectLater(
      service.readCurrent(
        vaultId: snapshot.accessContext.vaultId,
        entryId: snapshot.items.single.entryId,
        authority: authority,
      ),
      throwsFormatException,
    );
    expect(cache.states, isEmpty);
    expect(cache.active, isEmpty);
    expect(service.entries(snapshot.accessContext.vaultId), isEmpty);
  });

  test('logout invalidator clears the complete profile', () async {
    await service.synchronize(
      vaultId: snapshot.accessContext.vaultId,
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
      authority: authority,
      authoritativeMemberVaultKey: snapshot.memberVaultKey,
    );

    await service.clearCurrentEntryCache();

    expect(cache.states, isEmpty);
    expect(cache.active, isEmpty);
  });

  test('failed profile cleanup keeps every known Vault quarantined', () async {
    await service.synchronize(
      vaultId: snapshot.accessContext.vaultId,
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
      authority: authority,
      authoritativeMemberVaultKey: snapshot.memberVaultKey,
    );
    cache.failClearAll = true;

    await expectLater(service.purgeAll(), throwsStateError);

    expect(
      await service.readCurrent(
        vaultId: snapshot.accessContext.vaultId,
        entryId: snapshot.items.single.entryId,
        authority: authority,
      ),
      isNull,
    );
  });

  test('purge invalidates an in-flight delta before it can commit', () async {
    await service.synchronize(
      vaultId: snapshot.accessContext.vaultId,
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
      authority: authority,
      authoritativeMemberVaultKey: snapshot.memberVaultKey,
    );
    final pending = Completer<MemberDeltaResult>();
    remote.deltaCompleter = pending;
    final synchronization = service.synchronize(
      vaultId: snapshot.accessContext.vaultId,
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
      authority: authority,
      authoritativeMemberVaultKey: snapshot.memberVaultKey,
    );
    await Future<void>.delayed(Duration.zero);
    expect(remote.deltaRequests, 2);

    await service.purgeVault(snapshot.accessContext.vaultId);
    pending.complete(remote.deltaResult);

    await expectLater(synchronization, throwsA(isA<Exception>()));
    expect(cache.states, isEmpty);
    expect(cache.active, isEmpty);
  });

  test('failed durable purge keeps local reads quarantined', () async {
    await service.synchronize(
      vaultId: snapshot.accessContext.vaultId,
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: snapshot.accessContext.memberKeyGeneration,
      authority: authority,
      authoritativeMemberVaultKey: snapshot.memberVaultKey,
    );
    cache.failClearVault = true;

    await expectLater(
      service.purgeVault(snapshot.accessContext.vaultId),
      throwsStateError,
    );

    expect(
      await service.readCurrent(
        vaultId: snapshot.accessContext.vaultId,
        entryId: snapshot.items.single.entryId,
        authority: authority,
      ),
      isNull,
    );
  });
}
