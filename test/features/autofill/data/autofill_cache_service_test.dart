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
import 'package:mobile_palladin/features/vault/domain/repositories/vault_repository.dart';

class _MockVaultRepository extends Mock implements VaultRepository {}

class _MockEntryRepository extends Mock implements EntryRepository {}

class _MockBridge extends Mock implements AutoFillCacheBridge {}

void main() {
  late _MockVaultRepository vaultRepository;
  late _MockEntryRepository entryRepository;
  late _MockBridge bridge;
  late AutoFillCacheService service;

  setUpAll(() {
    registerFallbackValue(<AutoFillRecord>[]);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() async {
    vaultRepository = _MockVaultRepository();
    entryRepository = _MockEntryRepository();
    bridge = _MockBridge();
    service = AutoFillCacheService(
      vaultRepository: vaultRepository,
      entryRepository: entryRepository,
      bridge: bridge,
    );
    when(
      () => bridge.beginCacheSession(generation: any(named: 'generation')),
    ).thenAnswer((_) async {});
    when(
      () => bridge.replaceCache(any(), generation: any(named: 'generation')),
    ).thenAnswer((_) async {});
    when(
      () => bridge.revokeCacheAccess(generation: any(named: 'generation')),
    ).thenAnswer((_) async {});
    when(
      () => bridge.clearCache(generation: any(named: 'generation')),
    ).thenAnswer((_) async {});
    await service.beginSession();
  });

  test('normalizes URL hosts and rejects ambiguous identifiers', () {
    expect(
      AutoFillCacheService.normalizeDomain('https://WWW.Example.com/login'),
      'example.com',
    );
    expect(
      AutoFillCacheService.normalizeDomain('sub.example.com.'),
      'sub.example.com',
    );
    expect(AutoFillCacheService.normalizeDomain('localhost'), isNull);
    expect(AutoFillCacheService.normalizeDomain('not a host'), isNull);
  });

  test('decrypts credential entries and replaces the native cache', () async {
    final vault = _vault();
    final entry = _entry();
    when(vaultRepository.listVaults).thenAnswer((_) async => [vault]);
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
                generation: any(named: 'generation'),
              ),
            ).captured.single
            as List<AutoFillRecord>;
    expect(records, hasLength(1));
    expect(records.single.id, entry.id);
    expect(records.single.username, 'alice@example.com');
    expect(records.single.password, 'secret-value');
    expect(records.single.domains, ['example.com', 'login.example.com']);
  });

  test('clears stale cache before a mutation-triggered rebuild', () async {
    when(vaultRepository.listVaults).thenAnswer((_) async => const []);

    await service.clearAndSynchronize(privateKey: Uint8List(32));

    verifyInOrder([
      () => bridge.clearCache(generation: any(named: 'generation')),
      () => bridge.replaceCache(any(), generation: any(named: 'generation')),
    ]);
  });

  test('logout invalidates an active synchronization before replace', () async {
    final listStarted = Completer<void>();
    final vaults = Completer<List<VaultEntity>>();
    when(vaultRepository.listVaults).thenAnswer((_) {
      listStarted.complete();
      return vaults.future;
    });

    final synchronization = service.synchronize(privateKey: Uint8List(32));
    await listStarted.future;
    final logoutClear = service.clear();
    vaults.complete(const []);

    await Future.wait([synchronization, logoutClear]);

    verify(
      () => bridge.clearCache(generation: any(named: 'generation')),
    ).called(2);
    verifyNever(
      () => bridge.replaceCache(any(), generation: any(named: 'generation')),
    );
  });

  test('access revocation bypasses the serialized identity queue', () async {
    final listStarted = Completer<void>();
    final vaults = Completer<List<VaultEntity>>();
    when(vaultRepository.listVaults).thenAnswer((_) {
      listStarted.complete();
      return vaults.future;
    });

    final synchronization = service.synchronize(privateKey: Uint8List(32));
    await listStarted.future;
    await service.revokeAccess();
    vaults.complete(const []);
    await synchronization;

    verify(
      () => bridge.revokeCacheAccess(generation: any(named: 'generation')),
    ).called(1);
    verifyNever(
      () => bridge.replaceCache(any(), generation: any(named: 'generation')),
    );
  });

  test(
    'logout wipe completes after an already active native replace',
    () async {
      final replaceStarted = Completer<void>();
      final allowReplace = Completer<void>();
      when(vaultRepository.listVaults).thenAnswer((_) async => const []);
      when(
        () => bridge.replaceCache(any(), generation: any(named: 'generation')),
      ).thenAnswer((_) async {
        replaceStarted.complete();
        await allowReplace.future;
      });

      final synchronization = service.synchronize(privateKey: Uint8List(32));
      await replaceStarted.future;
      final logoutClear = service.clear();

      verify(
        () => bridge.clearCache(generation: any(named: 'generation')),
      ).called(1);
      allowReplace.complete();
      await Future.wait([synchronization, logoutClear]);

      verify(
        () => bridge.clearCache(generation: any(named: 'generation')),
      ).called(1);
    },
  );

  test('revocation supersedes an already submitted replacement', () async {
    final replaceStarted = Completer<void>();
    final allowReplace = Completer<void>();
    int? replaceGeneration;
    int? revokeGeneration;
    when(vaultRepository.listVaults).thenAnswer((_) async => const []);
    when(
      () => bridge.replaceCache(any(), generation: any(named: 'generation')),
    ).thenAnswer((invocation) async {
      replaceGeneration = invocation.namedArguments[#generation] as int;
      replaceStarted.complete();
      await allowReplace.future;
    });
    when(
      () => bridge.revokeCacheAccess(generation: any(named: 'generation')),
    ).thenAnswer((invocation) async {
      revokeGeneration = invocation.namedArguments[#generation] as int;
    });

    final synchronization = service.synchronize(privateKey: Uint8List(32));
    await replaceStarted.future;
    await service.revokeAccess();

    expect(revokeGeneration, greaterThan(replaceGeneration!));

    allowReplace.complete();
    await synchronization;
  });

  test('revocation blocks writes until a new session begins', () async {
    final firstReplaceStarted = Completer<void>();
    final releaseFirstReplace = Completer<void>();
    var replaceCalls = 0;
    when(vaultRepository.listVaults).thenAnswer((_) async => const []);
    when(
      () => bridge.replaceCache(any(), generation: any(named: 'generation')),
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

    await service.beginSession();
    await service.synchronize(privateKey: Uint8List(32));
    expect(replaceCalls, 2);

    releaseFirstReplace.complete();
    await previousSession;
  });

  test('logout clear retries and propagates a native wipe failure', () async {
    when(
      () => bridge.clearCache(generation: any(named: 'generation')),
    ).thenThrow(PlatformException(code: 'AUTOFILL_CACHE_ERROR'));

    await expectLater(service.clear(), throwsA(isA<PlatformException>()));

    verify(
      () => bridge.clearCache(generation: any(named: 'generation')),
    ).called(3);
  });

  test('failed pre-sync clear never writes a replacement cache', () async {
    when(
      () => bridge.clearCache(generation: any(named: 'generation')),
    ).thenThrow(PlatformException(code: 'AUTOFILL_CACHE_ERROR'));

    await service.synchronize(privateKey: Uint8List(32));

    verifyNever(
      () => bridge.replaceCache(any(), generation: any(named: 'generation')),
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

    notifier.notifyInvalidated();
    notifier.notifyChanged();

    await events;
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

EntryEntity _entry() => EntryEntity(
  id: 'entry-1',
  vaultId: 'vault-1',
  label: 'Example',
  type: EntryType.credential,
  urlDomain: 'example.com',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
