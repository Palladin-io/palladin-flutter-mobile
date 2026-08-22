import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_bridge.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_service.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_record.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/data/services/member_index_preparation_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';

class _MockMemberIndexPreparationService extends Mock
    implements MemberIndexPreparer {}

class _MockEntryRepository extends Mock implements EntryRepository {}

class _MockBridge extends Mock implements AutoFillCacheBridge {}

class _MockMemberIndex extends Mock implements MemberIndexReader {}

void main() {
  late _MockMemberIndexPreparationService indexPreparation;
  late _MockEntryRepository entryRepository;
  late _MockBridge bridge;
  late _MockMemberIndex memberIndex;
  late AutoFillCacheService service;

  setUpAll(() {
    registerFallbackValue(<AutoFillRecord>[]);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() async {
    indexPreparation = _MockMemberIndexPreparationService();
    entryRepository = _MockEntryRepository();
    bridge = _MockBridge();
    memberIndex = _MockMemberIndex();
    service = AutoFillCacheService(
      indexPreparation: indexPreparation,
      entryRepository: entryRepository,
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
    final vault = _vault();
    final entry = _entry();
    when(
      () => indexPreparation.prepare(any()),
    ).thenAnswer((_) async => [vault]);
    when(() => memberIndex.entries(vault.id)).thenReturn(const [
      MemberIndexEntry(
        entryId: 'entry-1',
        entryType: 1,
        memberLabel: 'Local Example',
        searchFields: [],
        revision: 'r-1',
        state: MemberEntryState.active,
        autofillDomains: ['https://login.example.com/path'],
      ),
    ]);
    when(
      () => entryRepository.revealAutoFillCredentials(
        vaultId: vault.id,
        privateKey: any(named: 'privateKey'),
        wrappedVK: any(named: 'wrappedVK'),
      ),
    ).thenAnswer(
      (_) async => [
        RevealedEntry(
          entry: entry,
          payload: const CredentialPayload(
            username: 'alice@example.com',
            password: 'secret-value',
            url: 'https://login.example.com/path',
          ).toJson(),
        ),
      ],
    );

    await service.synchronize(privateKey: Uint8List(32));

    final records =
        verify(
              () => bridge.replaceCache(
                captureAny(),
                sessionToken: any(named: 'sessionToken'),
              ),
            ).captured.single
            as List<AutoFillRecord>;
    expect(records, hasLength(1));
    expect(records.single.id, entry.id);
    expect(records.single.username, 'alice@example.com');
    expect(records.single.password, 'secret-value');
    expect(records.single.label, 'Local Example');
    expect(records.single.domains, ['login.example.com']);
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
        () => entryRepository.revealAutoFillCredentials(
          vaultId: any(named: 'vaultId'),
          privateKey: any(named: 'privateKey'),
          wrappedVK: any(named: 'wrappedVK'),
        ),
      );
      final records =
          verify(
                () => bridge.replaceCache(
                  captureAny(),
                  sessionToken: any(named: 'sessionToken'),
                ),
              ).captured.single
              as List<AutoFillRecord>;
      expect(records, isEmpty);
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
      () => entryRepository.revealAutoFillCredentials(
        vaultId: any(named: 'vaultId'),
        privateKey: any(named: 'privateKey'),
        wrappedVK: any(named: 'wrappedVK'),
      ),
    );
    final records =
        verify(
              () => bridge.replaceCache(
                captureAny(),
                sessionToken: any(named: 'sessionToken'),
              ),
            ).captured.single
            as List<AutoFillRecord>;
    expect(records, isEmpty);
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
      () => entryRepository.revealAutoFillCredentials(
        vaultId: vault.id,
        privateKey: any(named: 'privateKey'),
        wrappedVK: vault.wrappedVK,
      ),
    ).thenAnswer(
      (_) async => [
        RevealedEntry(
          entry: _entry(),
          payload: const CredentialPayload(
            username: 'alice',
            password: 'secret',
            notes: 'never',
            totp: 'never',
          ).toJson(),
        ),
      ],
    );

    await service.synchronize(privateKey: Uint8List(32));

    final records =
        verify(
              () => bridge.replaceCache(
                captureAny(),
                sessionToken: any(named: 'sessionToken'),
              ),
            ).captured.single
            as List<AutoFillRecord>;
    expect(records, isEmpty);
  });

  test(
    'platform record releases only identity, username, password and origins',
    () {
      const record = AutoFillRecord(
        id: 'id',
        label: 'label',
        username: 'user',
        password: 'password',
        domains: ['example.com'],
      );
      expect(record.toPlatformMap().keys, {
        'id',
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
      () =>
          bridge.replaceCache(any(), sessionToken: any(named: 'sessionToken')),
    ]);
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
      when(
        () => indexPreparation.prepare(any()),
      ).thenAnswer((_) async => const []);
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
    when(
      () => indexPreparation.prepare(any()),
    ).thenAnswer((_) async => const []);
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
    when(
      () => indexPreparation.prepare(any()),
    ).thenAnswer((_) async => const []);
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
      when(
        () => indexPreparation.prepare(any()),
      ).thenAnswer((_) async => const []);
      final recreated = AutoFillCacheService(
        indexPreparation: indexPreparation,
        entryRepository: entryRepository,
        bridge: bridge,
        memberIndex: memberIndex,
      );

      await recreated.beginSession();
      await recreated.synchronize(privateKey: Uint8List(32));

      verify(() => bridge.replaceCache(any(), sessionToken: 41)).called(1);
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

EntryEntity _entry() => EntryEntity(
  id: 'entry-1',
  vaultId: 'vault-1',
  label: 'Example',
  type: EntryType.credential,
  urlDomain: 'example.com',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  currentRevision: 'r-1',
);
