import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_bridge.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_service.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_record.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/data/services/member_index_preparation_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';

class _MockMemberIndexPreparationService extends Mock
    implements MemberIndexPreparer {}

class _MockLocalCurrentEntryService extends Mock
    implements LocalCurrentEntryService {}

class _MockBridge extends Mock implements AutoFillCacheBridge {}

class _MockMemberIndex extends Mock implements MemberIndexReader {}

void main() {
  late _MockMemberIndexPreparationService indexPreparation;
  late _MockLocalCurrentEntryService localEntries;
  late _MockBridge bridge;
  late _MockMemberIndex memberIndex;
  late AutoFillCacheService service;

  setUpAll(() {
    registerFallbackValue(_payload());
    registerFallbackValue(Uint8List(0));
  });

  setUp(() async {
    indexPreparation = _MockMemberIndexPreparationService();
    localEntries = _MockLocalCurrentEntryService();
    bridge = _MockBridge();
    memberIndex = _MockMemberIndex();
    service = AutoFillCacheService(
      indexPreparation: indexPreparation,
      localEntries: localEntries,
      bridge: bridge,
      memberIndex: memberIndex,
    );
    when(bridge.beginCacheSession).thenAnswer((_) async => 1);
    when(() => memberIndex.entries(any())).thenReturn(const []);
    when(
      () =>
          bridge.replaceCache(any(), sessionToken: any(named: 'sessionToken')),
    ).thenAnswer((_) async {});
    when(bridge.revokeCacheAccess).thenAnswer((_) async => 2);
    when(
      () => bridge.clearCache(sessionToken: any(named: 'sessionToken')),
    ).thenAnswer((_) async {});
    await service.beginSession();
  });

  void stubCredentialRebuild({String revision = 'r-1', int keyVersion = 1}) {
    final vault = _vault();
    when(
      () => indexPreparation.prepare(any()),
    ).thenAnswer((_) async => [vault]);
    when(() => memberIndex.entries(vault.id)).thenReturn([
      MemberIndexEntry(
        entryId: 'entry-1',
        entryType: EntryType.credential.toWire(),
        memberLabel: 'Local Example',
        searchFields: const [],
        revision: revision,
        currentKeyVersion: keyVersion,
        state: MemberEntryState.active,
        autofillDomains: const ['https://login.example.com/path'],
      ),
    ]);
    when(
      () => localEntries.revealCurrentWithAuthority(
        vaultId: vault.id,
        entryId: 'entry-1',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer(
      (_) async => _reveal(revision: revision, keyVersion: keyVersion),
    );
  }

  test('normalizes URL hosts and rejects ambiguous identifiers', () {
    expect(
      AutoFillCacheService.normalizeDomain('https://WWW.Example.com/login'),
      'www.example.com',
    );
    expect(
      AutoFillCacheService.normalizeDomain('sub.example.com.'),
      'sub.example.com',
    );
    expect(AutoFillCacheService.normalizeDomain('localhost'), isNull);
    expect(AutoFillCacheService.normalizeDomain('not a host'), isNull);
    expect(
      AutoFillCacheService.normalizeDomain('https://user@example.com'),
      isNull,
    );
    expect(
      AutoFillCacheService.normalizeDomain('https://example.com:443'),
      isNull,
    );
    expect(AutoFillCacheService.normalizeDomain('https://exаmple.com'), isNull);
    expect(AutoFillCacheService.normalizeDomain('*.example.com'), isNull);
  });

  test('decrypts credential entries and replaces the native cache', () async {
    stubCredentialRebuild();

    await service.synchronize(privateKey: Uint8List(32));

    final payload =
        verify(
              () => bridge.replaceCache(
                captureAny(),
                sessionToken: any(named: 'sessionToken'),
              ),
            ).captured.single
            as AutoFillCachePayload;
    final records = payload.records;
    expect(records, hasLength(1));
    expect(records.single.id, 'entry-1');
    expect(records.single.username, 'alice@example.com');
    expect(records.single.password, 'secret-value');
    expect(records.single.label, 'Local Example');
    expect(records.single.domains, ['login.example.com']);
    expect(payload.manifest.organizationId, 'org-1');
    expect(
      payload.manifest.vaults['vault-1']!.entries['entry-1']!.revision,
      'r-1',
    );
    verify(
      () => localEntries.revealCurrentWithAuthority(
        vaultId: 'vault-1',
        entryId: 'entry-1',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).called(1);
  });

  test(
    'archived, deleted and corrupt MemberIndex rows never decrypt',
    () async {
      final vault = _vault();
      when(
        () => indexPreparation.prepare(any()),
      ).thenAnswer((_) async => [vault]);
      when(() => memberIndex.entries(vault.id)).thenReturn(const [
        MemberIndexEntry(
          entryId: 'archived',
          entryType: 1,
          memberLabel: 'A',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.archived,
          autofillDomains: ['example.com'],
        ),
        MemberIndexEntry(
          entryId: 'deleted',
          entryType: 1,
          memberLabel: 'D',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.deleted,
          autofillDomains: ['example.com'],
        ),
        MemberIndexEntry(
          entryId: 'corrupt',
          entryType: 1,
          memberLabel: 'C',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.active,
          autofillDomains: ['example.com'],
          corrupt: true,
        ),
      ]);

      await service.synchronize(privateKey: Uint8List(32));

      verifyNever(
        () => localEntries.revealCurrentWithAuthority(
          vaultId: any(named: 'vaultId'),
          entryId: any(named: 'entryId'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      );
      verifyNever(
        () => bridge.replaceCache(
          any(),
          sessionToken: any(named: 'sessionToken'),
        ),
      );
    },
  );

  test('credit-card entries are never eligible for AutoFill', () async {
    final vault = _vault();
    when(
      () => indexPreparation.prepare(any()),
    ).thenAnswer((_) async => [vault]);
    when(() => memberIndex.entries(vault.id)).thenReturn([
      MemberIndexEntry(
        entryId: 'card-entry',
        entryType: EntryType.creditCard.toWire(),
        memberLabel: 'Travel card',
        searchFields: const [],
        revision: '1',
        state: MemberEntryState.active,
        autofillDomains: const ['checkout.example.com'],
      ),
    ]);

    await service.synchronize(privateKey: Uint8List(32));

    verifyNever(
      () => localEntries.revealCurrentWithAuthority(
        vaultId: any(named: 'vaultId'),
        entryId: any(named: 'entryId'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    );
    verifyNever(
      () =>
          bridge.replaceCache(any(), sessionToken: any(named: 'sessionToken')),
    );
  });

  test('stale secret revision is rejected after decryption', () async {
    final vault = _vault();
    when(
      () => indexPreparation.prepare(any()),
    ).thenAnswer((_) async => [vault]);
    when(() => memberIndex.entries(vault.id)).thenReturn(const [
      MemberIndexEntry(
        entryId: 'entry-1',
        entryType: 1,
        memberLabel: 'Example',
        searchFields: [],
        revision: 'newer',
        state: MemberEntryState.active,
        autofillDomains: ['example.com'],
      ),
    ]);
    when(
      () => localEntries.revealCurrentWithAuthority(
        vaultId: vault.id,
        entryId: 'entry-1',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => _reveal(revision: 'r-1'));

    await service.synchronize(privateKey: Uint8List(32));

    verifyNever(
      () =>
          bridge.replaceCache(any(), sessionToken: any(named: 'sessionToken')),
    );
  });

  test(
    'platform record releases only identity, username, password and origins',
    () {
      const record = AutoFillRecord(
        id: 'id',
        organizationId: 'org',
        vaultId: 'vault',
        revision: '1',
        keyVersion: 1,
        label: 'label',
        username: 'user',
        password: 'password',
        domains: ['example.com'],
      );
      expect(record.toPlatformMap().keys, {
        'id',
        'organizationId',
        'vaultId',
        'revision',
        'keyVersion',
        'label',
        'username',
        'password',
        'domains',
      });
      expect(record.toPlatformMap(), isNot(contains('notes')));
      expect(record.toPlatformMap(), isNot(contains('totp')));
    },
  );

  test('clears stale cache before a mutation-triggered rebuild', () async {
    when(
      () => indexPreparation.prepare(any(), ensureFresh: true),
    ).thenAnswer((_) async => const []);

    await service.clearAndSynchronize(privateKey: Uint8List(32));

    verifyInOrder([
      () => bridge.clearCache(sessionToken: any(named: 'sessionToken')),
    ]);
    verifyNever(
      () =>
          bridge.replaceCache(any(), sessionToken: any(named: 'sessionToken')),
    );
  });

  test('logout invalidates an active synchronization before replace', () async {
    final listStarted = Completer<void>();
    final vaults = Completer<List<VaultEntity>>();
    when(() => indexPreparation.prepare(any())).thenAnswer((_) {
      listStarted.complete();
      return vaults.future;
    });

    final synchronization = service.synchronize(privateKey: Uint8List(32));
    await listStarted.future;
    final logoutClear = service.clear();
    vaults.complete(const []);

    await Future.wait([synchronization, logoutClear]);

    verify(
      () => bridge.clearCache(sessionToken: any(named: 'sessionToken')),
    ).called(2);
    verifyNever(
      () =>
          bridge.replaceCache(any(), sessionToken: any(named: 'sessionToken')),
    );
  });

  test('access revocation bypasses the serialized identity queue', () async {
    final listStarted = Completer<void>();
    final vaults = Completer<List<VaultEntity>>();
    when(() => indexPreparation.prepare(any())).thenAnswer((_) {
      listStarted.complete();
      return vaults.future;
    });

    final synchronization = service.synchronize(privateKey: Uint8List(32));
    await listStarted.future;
    await service.revokeAccess();
    vaults.complete(const []);
    await synchronization;

    verify(bridge.revokeCacheAccess).called(1);
    verifyNever(
      () =>
          bridge.replaceCache(any(), sessionToken: any(named: 'sessionToken')),
    );
  });

  test(
    'logout wipe completes after an already active native replace',
    () async {
      final replaceStarted = Completer<void>();
      final allowReplace = Completer<void>();
      stubCredentialRebuild();
      when(
        () => bridge.replaceCache(
          any(),
          sessionToken: any(named: 'sessionToken'),
        ),
      ).thenAnswer((_) async {
        replaceStarted.complete();
        await allowReplace.future;
      });

      final synchronization = service.synchronize(privateKey: Uint8List(32));
      await replaceStarted.future;
      final logoutClear = service.clear();

      verify(
        () => bridge.clearCache(sessionToken: any(named: 'sessionToken')),
      ).called(1);
      allowReplace.complete();
      await Future.wait([synchronization, logoutClear]);

      verify(
        () => bridge.clearCache(sessionToken: any(named: 'sessionToken')),
      ).called(1);
    },
  );

  test('revocation supersedes an already submitted replacement', () async {
    final replaceStarted = Completer<void>();
    final allowReplace = Completer<void>();
    int? replacementToken;
    stubCredentialRebuild();
    when(
      () =>
          bridge.replaceCache(any(), sessionToken: any(named: 'sessionToken')),
    ).thenAnswer((invocation) async {
      replacementToken = invocation.namedArguments[#sessionToken] as int;
      replaceStarted.complete();
      await allowReplace.future;
    });
    when(bridge.revokeCacheAccess).thenAnswer((_) async => 2);

    final synchronization = service.synchronize(privateKey: Uint8List(32));
    await replaceStarted.future;
    await service.revokeAccess();

    expect(replacementToken, 1);
    verify(bridge.revokeCacheAccess).called(1);

    allowReplace.complete();
    await synchronization;
  });

  test('revocation blocks writes until a new session begins', () async {
    final firstReplaceStarted = Completer<void>();
    final releaseFirstReplace = Completer<void>();
    var replaceCalls = 0;
    stubCredentialRebuild();
    when(
      () =>
          bridge.replaceCache(any(), sessionToken: any(named: 'sessionToken')),
    ).thenAnswer((_) async {
      replaceCalls += 1;
      if (replaceCalls == 1) {
        firstReplaceStarted.complete();
        await releaseFirstReplace.future;
      }
    });

    final previousSession = service.synchronize(privateKey: Uint8List(32));
    await firstReplaceStarted.future;
    await service.revokeAccess();

    await service.synchronize(privateKey: Uint8List(32));
    expect(replaceCalls, 1);

    when(bridge.beginCacheSession).thenAnswer((_) async => 3);
    await service.beginSession();
    await service.synchronize(privateKey: Uint8List(32));
    expect(replaceCalls, 2);

    releaseFirstReplace.complete();
    await previousSession;
  });

  test(
    'a recreated Dart service obtains a fresh native session token',
    () async {
      await service.revokeAccess();
      when(bridge.beginCacheSession).thenAnswer((_) async => 41);
      stubCredentialRebuild();
      final recreated = AutoFillCacheService(
        indexPreparation: indexPreparation,
        localEntries: localEntries,
        bridge: bridge,
        memberIndex: memberIndex,
      );

      await recreated.beginSession();
      await recreated.synchronize(privateKey: Uint8List(32));

      verify(() => bridge.replaceCache(any(), sessionToken: 41)).called(1);
    },
  );

  test(
    'an older overlapping begin callback cannot revoke the newer session',
    () async {
      clearInteractions(bridge);
      final older = Completer<int>();
      final newer = Completer<int>();
      var calls = 0;
      when(bridge.beginCacheSession).thenAnswer((_) {
        calls += 1;
        return calls == 1 ? older.future : newer.future;
      });
      stubCredentialRebuild();

      final olderBegin = service.beginSession();
      final newerBegin = service.beginSession();
      newer.complete(3);
      await newerBegin;
      older.complete(2);
      await olderBegin;
      await service.synchronize(privateKey: Uint8List(32));

      verifyNever(bridge.revokeCacheAccess);
      verify(() => bridge.replaceCache(any(), sessionToken: 3)).called(1);
    },
  );

  test(
    'a late old revoke callback cannot overwrite the newer session token',
    () async {
      final oldRevokeResult = Completer<int>();
      when(bridge.revokeCacheAccess).thenAnswer((_) => oldRevokeResult.future);
      final oldRevoke = service.revokeAccess();

      when(bridge.beginCacheSession).thenAnswer((_) async => 9);
      await service.beginSession();
      oldRevokeResult.complete(2);
      await oldRevoke;
      stubCredentialRebuild();

      await service.synchronize(privateKey: Uint8List(32));
      await service.clear();

      verify(() => bridge.replaceCache(any(), sessionToken: 9)).called(1);
      verify(() => bridge.clearCache(sessionToken: 9)).called(2);
      verifyNever(() => bridge.clearCache(sessionToken: 2));
    },
  );

  test('logout clear retries and propagates a native wipe failure', () async {
    when(
      () => bridge.clearCache(sessionToken: any(named: 'sessionToken')),
    ).thenThrow(PlatformException(code: 'AUTOFILL_CACHE_ERROR'));

    await expectLater(service.clear(), throwsA(isA<PlatformException>()));

    verify(
      () => bridge.clearCache(sessionToken: any(named: 'sessionToken')),
    ).called(3);
  });

  test(
    'pre-fence revoke failure preserves the session token for fallback clear',
    () async {
      when(
        bridge.revokeCacheAccess,
      ).thenThrow(PlatformException(code: 'AUTOFILL_REVOKE_PRE_FENCE'));

      await expectLater(
        service.revokeAccess(),
        throwsA(isA<PlatformException>()),
      );
      await service.clear();

      verify(() => bridge.clearCache(sessionToken: 1)).called(1);
    },
  );

  test('stale fallback clear requires a confirmed emergency revoke', () async {
    var revokeCalls = 0;
    when(bridge.revokeCacheAccess).thenAnswer((_) async {
      revokeCalls += 1;
      if (revokeCalls == 1) {
        throw PlatformException(code: 'AUTOFILL_REVOKE_PRE_FENCE');
      }
      return 3;
    });
    when(
      () => bridge.clearCache(sessionToken: 1),
    ).thenThrow(PlatformException(code: 'AUTOFILL_STALE_SESSION'));

    await expectLater(
      service.revokeAccess(),
      throwsA(isA<PlatformException>()),
    );
    await service.clear();

    expect(revokeCalls, 2);
    verify(() => bridge.clearCache(sessionToken: 1)).called(3);
  });

  test(
    'failed fallback clear and emergency revoke remain fail closed',
    () async {
      when(
        bridge.revokeCacheAccess,
      ).thenThrow(PlatformException(code: 'AUTOFILL_REVOKE_PRE_FENCE'));
      when(
        () => bridge.clearCache(sessionToken: 1),
      ).thenThrow(PlatformException(code: 'AUTOFILL_STALE_SESSION'));

      await expectLater(
        service.revokeAccess(),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(service.clear(), throwsA(isA<PlatformException>()));

      verify(() => bridge.clearCache(sessionToken: 1)).called(3);
      verify(bridge.revokeCacheAccess).called(2);
    },
  );

  test('failed native session activation makes mutation clear fail', () async {
    when(
      bridge.beginCacheSession,
    ).thenThrow(PlatformException(code: 'AUTOFILL_CACHE_ERROR'));

    await service.beginSession();

    await expectLater(service.clear(), throwsA(isA<PlatformException>()));
    verifyNever(
      () => bridge.clearCache(sessionToken: any(named: 'sessionToken')),
    );
  });

  test(
    'missing native plugin keeps mutation clear a supported no-op',
    () async {
      when(bridge.beginCacheSession).thenThrow(MissingPluginException());

      await service.beginSession();
      await service.clear();

      verifyNever(
        () => bridge.clearCache(sessionToken: any(named: 'sessionToken')),
      );
    },
  );

  test('failed pre-sync clear never writes a replacement cache', () async {
    when(
      () => bridge.clearCache(sessionToken: any(named: 'sessionToken')),
    ).thenThrow(PlatformException(code: 'AUTOFILL_CACHE_ERROR'));

    await service.synchronize(privateKey: Uint8List(32));

    verifyNever(
      () =>
          bridge.replaceCache(any(), sessionToken: any(named: 'sessionToken')),
    );
  });

  test(
    'policy-2 complete fixture rebuild uses only local canonical material',
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
      final item = snapshot.items.single;
      expect(item.entryKey, isNotNull);
      expect(item.memberIndex, isNotNull);
      expect(item.memberSecret, isNotNull);
      final expectedSecret = Map<String, dynamic>.from(
        ((fixture['cryptoEvidence'] as Map)['expectedMemberSecretPlaintext']
            as Map),
      );
      final expectedIndex = Map<String, dynamic>.from(
        ((fixture['cryptoEvidence'] as Map)['expectedMemberIndexPlaintext']
            as Map),
      );
      final expectedContent = Map<String, dynamic>.from(
        expectedSecret['content']! as Map,
      );
      when(
        () => memberIndex.entries(snapshot.accessContext.vaultId),
      ).thenReturn([
        MemberIndexEntry(
          entryId: item.entryId,
          entryType: expectedIndex['entryType']! as int,
          memberLabel: expectedIndex['memberLabel']! as String,
          searchFields: List<String>.from(
            expectedIndex['searchFields']! as List,
          ),
          revision: item.currentRevision!,
          currentKeyVersion: item.currentKeyVersion!,
          state: MemberEntryState.active,
          autofillDomains: const ['fixture.invalid'],
        ),
      ]);
      when(
        () => localEntries.revealCurrentWithAuthority(
          vaultId: snapshot.accessContext.vaultId,
          entryId: item.entryId,
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer(
        (_) async => _revealFor(
          entryId: item.entryId,
          organizationId: snapshot.accessContext.organizationId,
          vaultId: snapshot.accessContext.vaultId,
          revision: item.currentRevision!,
          keyVersion: item.currentKeyVersion!,
          username: expectedContent['username']! as String,
          password: expectedContent['password']! as String,
          accessContext: snapshot.accessContext,
        ),
      );

      await service.synchronizePrepared(
        privateKey: Uint8List(32),
        vaultIds: [snapshot.accessContext.vaultId],
      );

      final payload =
          verify(
                () => bridge.replaceCache(
                  captureAny(),
                  sessionToken: any(named: 'sessionToken'),
                ),
              ).captured.single
              as AutoFillCachePayload;
      expect(payload.records.single.id, item.entryId);
      expect(payload.records.single.revision, item.currentRevision);
      expect(payload.records.single.keyVersion, item.currentKeyVersion);
      expect(payload.records.single.password, 'not-a-real-password');
      verifyNever(() => indexPreparation.prepare(any()));

      final source = File(
        'lib/features/autofill/data/autofill_cache_service.dart',
      ).readAsStringSync();
      for (final forbidden in [
        'listEntries(',
        'getEntry(',
        'revealAutoFillCredentials(',
      ]) {
        expect(source, isNot(contains(forbidden)));
      }
    },
  );

  test(
    'committed prepared rebuild makes zero requests and exact mutation sets',
    () async {
      var networkRequests = 3; // paginated snapshot + closing delta baseline
      var entries = <MemberIndexEntry>[];
      var context = _accessContext();
      final replacements = <AutoFillCachePayload>[];
      when(() => memberIndex.entries('vault-1')).thenAnswer((_) => entries);
      when(
        () => indexPreparation.prepare(
          any(),
          ensureFresh: any(named: 'ensureFresh'),
        ),
      ).thenAnswer((_) async {
        networkRequests += 1;
        return const [];
      });
      when(
        () => localEntries.revealCurrentWithAuthority(
          vaultId: 'vault-1',
          entryId: any(named: 'entryId'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((invocation) async {
        final entryId = invocation.namedArguments[#entryId]! as String;
        final index = entries.lastWhere((entry) => entry.entryId == entryId);
        return _revealFor(
          entryId: entryId,
          revision: index.revision,
          keyVersion: index.currentKeyVersion,
          username: '$entryId-user',
          password: '$entryId-password',
          accessContext: context,
        );
      });
      when(
        () => bridge.replaceCache(
          any(),
          sessionToken: any(named: 'sessionToken'),
        ),
      ).thenAnswer((invocation) async {
        replacements.add(
          invocation.positionalArguments.single as AutoFillCachePayload,
        );
      });

      Future<void> expectTransition({
        required String name,
        required List<MemberIndexEntry> next,
        required List<String> expectedIds,
        MemberOfflineAccessContext? nextContext,
      }) async {
        entries = next;
        context = nextContext ?? _accessContext();
        final before = replacements.length;
        await service.synchronizePrepared(
          privateKey: Uint8List(32),
          vaultIds: const ['vault-1'],
        );
        expect(networkRequests, 3, reason: '$name must remain local-only');
        if (expectedIds.isEmpty) {
          expect(replacements.length, before, reason: name);
          return;
        }
        expect(replacements.length, before + 1, reason: name);
        final ids = replacements.last.records
            .map((record) => record.id)
            .toList();
        expect(ids, expectedIds, reason: name);
        expect(ids.toSet(), hasLength(ids.length), reason: '$name duplicates');
      }

      final entry1 = _indexEntry('entry-1');
      final entry2 = _indexEntry('entry-2');
      await expectTransition(
        name: 'create',
        next: [entry1],
        expectedIds: ['entry-1'],
      );
      await expectTransition(
        name: 'update',
        next: [_indexEntry('entry-1', revision: '2')],
        expectedIds: ['entry-1'],
      );
      await expectTransition(
        name: 'import',
        next: [entry1, entry2],
        expectedIds: ['entry-1', 'entry-2'],
      );
      await expectTransition(
        name: 'archive',
        next: [
          _indexEntry('entry-1', state: MemberEntryState.archived),
          entry2,
        ],
        expectedIds: ['entry-2'],
      );
      await expectTransition(
        name: 'restore',
        next: [entry1, entry2],
        expectedIds: ['entry-1', 'entry-2'],
      );
      await expectTransition(
        name: 'delete',
        next: [
          _indexEntry('entry-1', state: MemberEntryState.deleted),
          entry2,
        ],
        expectedIds: ['entry-2'],
      );
      await expectTransition(
        name: 'policy disabled',
        next: [entry2],
        expectedIds: const [],
        nextContext: _accessContext(offlinePolicy: 'disabled'),
      );
      await expectTransition(
        name: 'AgentVisibility mutation',
        next: [_indexEntry('entry-2', revision: '3')],
        expectedIds: ['entry-2'],
      );
      await expectTransition(
        name: 'rekey',
        next: [_indexEntry('entry-2', revision: '4', keyVersion: 2)],
        expectedIds: ['entry-2'],
      );
      await expectTransition(
        name: 'reconnect',
        next: [_indexEntry('entry-2', revision: '4', keyVersion: 2)],
        expectedIds: ['entry-2'],
      );
    },
  );

  test(
    'zero-candidate prepared transition clears the previous native cache',
    () async {
      when(() => memberIndex.entries('vault-1')).thenReturn(const []);

      await service.synchronizePrepared(
        privateKey: Uint8List(32),
        vaultIds: const ['vault-1'],
      );

      verify(() => bridge.clearCache(sessionToken: 1)).called(1);
      verifyNever(
        () => bridge.replaceCache(
          any(),
          sessionToken: any(named: 'sessionToken'),
        ),
      );
      verifyNever(() => indexPreparation.prepare(any()));
    },
  );

  test(
    'a commit for Vault A retains B and a purged B removes only B',
    () async {
      var vaultBEntries = <MemberIndexEntry>[_indexEntry('entry-b')];
      when(
        () => memberIndex.entries('vault-a'),
      ).thenReturn([_indexEntry('entry-a')]);
      when(
        () => memberIndex.entries('vault-b'),
      ).thenAnswer((_) => vaultBEntries);
      when(
        () => localEntries.revealCurrentWithAuthority(
          vaultId: any(named: 'vaultId'),
          entryId: any(named: 'entryId'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((invocation) async {
        final vaultId = invocation.namedArguments[#vaultId]! as String;
        final entryId = invocation.namedArguments[#entryId]! as String;
        return _revealFor(
          entryId: entryId,
          vaultId: vaultId,
          accessContext: _accessContext(vaultId: vaultId),
        );
      });

      await service.synchronizePrepared(
        privateKey: Uint8List(32),
        vaultIds: const ['vault-a', 'vault-b'],
      );
      final first =
          verify(
                () => bridge.replaceCache(
                  captureAny(),
                  sessionToken: any(named: 'sessionToken'),
                ),
              ).captured.single
              as AutoFillCachePayload;
      expect(first.records.map((record) => record.id).toSet(), {
        'entry-a',
        'entry-b',
      });

      vaultBEntries = const [];
      await service.synchronizePrepared(
        privateKey: Uint8List(32),
        vaultIds: const ['vault-a', 'vault-b'],
      );
      final second =
          verify(
                () => bridge.replaceCache(
                  captureAny(),
                  sessionToken: any(named: 'sessionToken'),
                ),
              ).captured.single
              as AutoFillCachePayload;
      expect(second.records.map((record) => record.id), ['entry-a']);
    },
  );

  test(
    'every full Vault access-context field is independently consistent',
    () async {
      final mutations = <String, MemberOfflineAccessContext Function()>{
        'contextVersion': () => _accessContext(contextVersion: 2),
        'memberId': () => _accessContext(memberId: 'other-member'),
        'memberRecipientKeyVersion': () =>
            _accessContext(memberRecipientKeyVersion: 6),
        'memberRecipientKeyFingerprint': () =>
            _accessContext(memberRecipientKeyFingerprint: 'other-fingerprint'),
        'issuedAt': () =>
            _accessContext(issuedAt: DateTime.utc(2026, 8, 29, 1)),
      };
      when(
        () => memberIndex.entries('vault-1'),
      ).thenReturn([_indexEntry('entry-1'), _indexEntry('entry-2')]);
      MemberOfflineAccessContext secondContext = _accessContext();
      when(
        () => localEntries.revealCurrentWithAuthority(
          vaultId: 'vault-1',
          entryId: any(named: 'entryId'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((invocation) async {
        final entryId = invocation.namedArguments[#entryId]! as String;
        return _revealFor(
          entryId: entryId,
          accessContext: entryId == 'entry-1'
              ? _accessContext()
              : secondContext,
        );
      });

      for (final mutation in mutations.entries) {
        secondContext = mutation.value();
        await expectLater(
          service.synchronizePrepared(
            privateKey: Uint8List(32),
            vaultIds: const ['vault-1'],
          ),
          throwsFormatException,
          reason: mutation.key,
        );
      }
      verifyNever(
        () => bridge.replaceCache(
          any(),
          sessionToken: any(named: 'sessionToken'),
        ),
      );
    },
  );

  test('mutation notifier distinguishes invalidation from rebuild', () async {
    final notifier = AutoFillMutationNotifier();
    final events = expectLater(
      notifier.changes.take(2),
      emitsInOrder([
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]),
    );

    await notifier.notifyInvalidated();
    await notifier.notifyChanged();

    await events;
  });

  test('beginMutation waits for the native invalidation handler', () async {
    final notifier = AutoFillMutationNotifier();
    final invalidation = Completer<void>();
    notifier.attachHandler((action) async {
      if (action == AutoFillMutationAction.invalidate) {
        await invalidation.future;
      }
    });
    addTearDown(notifier.detachHandler);

    var leaseCreated = false;
    final pendingLease = notifier.beginMutation().then((lease) {
      leaseCreated = true;
      return lease;
    });
    await Future<void>.delayed(Duration.zero);

    expect(leaseCreated, isFalse);

    invalidation.complete();
    final lease = await pendingLease;
    expect(leaseCreated, isTrue);
    await lease.complete();
  });

  test(
    'overlapping mutations rebuild only after the whole batch is definitive',
    () async {
      final notifier = AutoFillMutationNotifier();
      final actions = <AutoFillMutationAction>[];
      final subscription = notifier.changes.listen(actions.add);
      addTearDown(subscription.cancel);

      final first = await notifier.beginMutation();
      final second = await notifier.beginMutation();
      await first.complete();
      await notifier.notifyChanged();

      expect(actions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.invalidate,
      ]);

      await second.complete();

      expect(actions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]);
    },
  );

  test(
    'an ambiguous overlapping mutation suppresses the batch rebuild',
    () async {
      final notifier = AutoFillMutationNotifier();
      final actions = <AutoFillMutationAction>[];
      final subscription = notifier.changes.listen(actions.add);
      addTearDown(subscription.cancel);

      final first = await notifier.beginMutation();
      final second = await notifier.beginMutation();
      await first.complete();
      await second.leaveAmbiguous();

      expect(actions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.invalidate,
      ]);

      final recovery = await notifier.beginMutation();
      await recovery.complete();

      expect(actions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]);
    },
  );

  test('standalone definitive change starts fresh after ambiguity', () async {
    final notifier = AutoFillMutationNotifier();
    final actions = <AutoFillMutationAction>[];
    final subscription = notifier.changes.listen(actions.add);
    addTearDown(subscription.cancel);

    final ambiguous = await notifier.beginMutation();
    await ambiguous.leaveAmbiguous();
    await notifier.notifyChanged();

    expect(actions, [
      AutoFillMutationAction.invalidate,
      AutoFillMutationAction.rebuild,
    ]);
  });
}

VaultEntity _vault() => VaultEntity(
  id: 'vault-1',
  name: 'Personal',
  grantMode: GrantMode.granular,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  entryCount: 1,
  activeGrantCount: 0,
  memberCount: 1,
  wrappedVK: 'wrapped-vk',
);

LocalCurrentEntryReveal _reveal({
  String revision = 'r-1',
  int keyVersion = 1,
  MemberOfflineAccessContext? accessContext,
}) => LocalCurrentEntryReveal(
  snapshot: CanonicalEntrySnapshot(
    entry: {
      'id': 'entry-1',
      'organizationId': 'org-1',
      'vaultId': 'vault-1',
      'state': 'active',
      'currentRevision': revision,
      'currentKeyVersion': keyVersion,
    },
    secret: <String, dynamic>{},
    payload: const CredentialPayload(
      username: 'alice@example.com',
      password: 'secret-value',
      url: 'https://login.example.com/path',
    ).toJson(),
  ),
  accessContext: accessContext ?? _accessContext(),
);

LocalCurrentEntryReveal _revealFor({
  required String entryId,
  String organizationId = 'org-1',
  String vaultId = 'vault-1',
  String revision = '1',
  int keyVersion = 1,
  String username = 'alice@example.com',
  String password = 'secret-value',
  MemberOfflineAccessContext? accessContext,
}) => LocalCurrentEntryReveal(
  snapshot: CanonicalEntrySnapshot(
    entry: {
      'id': entryId,
      'organizationId': organizationId,
      'vaultId': vaultId,
      'state': 'active',
      'currentRevision': revision,
      'currentKeyVersion': keyVersion,
    },
    secret: <String, dynamic>{},
    payload: CredentialPayload(
      username: username,
      password: password,
      url: 'https://fixture.invalid',
    ).toJson(),
  ),
  accessContext: accessContext ?? _accessContext(),
);

MemberIndexEntry _indexEntry(
  String entryId, {
  String revision = '1',
  int keyVersion = 1,
  MemberEntryState state = MemberEntryState.active,
}) => MemberIndexEntry(
  entryId: entryId,
  entryType: EntryType.credential.toWire(),
  memberLabel: entryId,
  searchFields: const [],
  revision: revision,
  currentKeyVersion: keyVersion,
  state: state,
  autofillDomains: const ['fixture.invalid'],
);

MemberOfflineAccessContext _accessContext({
  int contextVersion = 1,
  String memberId = 'principal-1',
  int memberRecipientKeyVersion = 5,
  String memberRecipientKeyFingerprint = 'fixture-fingerprint',
  String offlinePolicy = '24h',
  String vaultId = 'vault-1',
  DateTime? issuedAt,
}) => MemberOfflineAccessContext(
  contextVersion: contextVersion,
  principalId: 'principal-1',
  organizationId: 'org-1',
  organizationMembershipGeneration: '9',
  vaultId: vaultId,
  memberId: memberId,
  memberKeyGeneration: 4,
  vaultKeyVersion: 6,
  memberRecipientKeyVersion: memberRecipientKeyVersion,
  memberRecipientKeyFingerprint: memberRecipientKeyFingerprint,
  offlinePolicy: offlinePolicy,
  offlinePolicyVersion: 3,
  issuedAt: issuedAt ?? DateTime.utc(2026, 8, 29),
  notAfter: (issuedAt ?? DateTime.utc(2026, 8, 29)).add(switch (offlinePolicy) {
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '24h' => const Duration(hours: 24),
    _ => Duration.zero,
  }),
);

AutoFillCachePayload _payload() => AutoFillCachePayload(
  manifest: AutoFillCacheManifest(
    principalId: 'principal-1',
    organizationId: 'org-1',
    organizationMembershipGeneration: '9',
    offlinePolicy: '24h',
    offlinePolicyVersion: 3,
    vaults: {
      'vault-1': AutoFillVaultAuthority(
        contextVersion: 1,
        memberId: 'principal-1',
        memberKeyGeneration: 4,
        vaultKeyVersion: 6,
        memberRecipientKeyVersion: 5,
        memberRecipientKeyFingerprint: 'fixture-fingerprint',
        issuedAt: DateTime.utc(2026, 8, 29),
        notAfter: DateTime.utc(2026, 8, 30),
        entries: const {
          'entry-1': AutoFillEntryAuthority(revision: 'r-1', keyVersion: 1),
        },
      ),
    },
  ),
  records: const [
    AutoFillRecord(
      id: 'entry-1',
      organizationId: 'org-1',
      vaultId: 'vault-1',
      revision: 'r-1',
      keyVersion: 1,
      label: 'Example',
      username: 'alice',
      password: 'test-only-password',
      domains: ['example.com'],
    ),
  ],
);
