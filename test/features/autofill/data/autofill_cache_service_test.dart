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

  setUp(() {
    vaultRepository = _MockVaultRepository();
    entryRepository = _MockEntryRepository();
    bridge = _MockBridge();
    service = AutoFillCacheService(
      vaultRepository: vaultRepository,
      entryRepository: entryRepository,
      bridge: bridge,
    );
    when(() => bridge.replaceCache(any())).thenAnswer((_) async {});
    when(bridge.revokeCacheAccess).thenAnswer((_) async {});
    when(bridge.clearCache).thenAnswer((_) async {});
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
        verify(() => bridge.replaceCache(captureAny())).captured.single
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

    verifyInOrder([bridge.clearCache, () => bridge.replaceCache(any())]);
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

    verify(() => bridge.clearCache()).called(2);
    verifyNever(() => bridge.replaceCache(any()));
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

    verify(bridge.revokeCacheAccess).called(1);
    verifyNever(() => bridge.replaceCache(any()));
  });

  test(
    'logout wipe completes after an already active native replace',
    () async {
      final replaceStarted = Completer<void>();
      final allowReplace = Completer<void>();
      when(vaultRepository.listVaults).thenAnswer((_) async => const []);
      when(() => bridge.replaceCache(any())).thenAnswer((_) async {
        replaceStarted.complete();
        await allowReplace.future;
      });

      final synchronization = service.synchronize(privateKey: Uint8List(32));
      await replaceStarted.future;
      final logoutClear = service.clear();

      verify(() => bridge.clearCache()).called(1);
      allowReplace.complete();
      await Future.wait([synchronization, logoutClear]);

      verify(() => bridge.clearCache()).called(1);
    },
  );

  test('logout clear retries and propagates a native wipe failure', () async {
    when(
      bridge.clearCache,
    ).thenThrow(PlatformException(code: 'AUTOFILL_CACHE_ERROR'));

    await expectLater(service.clear(), throwsA(isA<PlatformException>()));

    verify(() => bridge.clearCache()).called(3);
  });

  test('failed pre-sync clear never writes a replacement cache', () async {
    when(
      bridge.clearCache,
    ).thenThrow(PlatformException(code: 'AUTOFILL_CACHE_ERROR'));

    await service.synchronize(privateKey: Uint8List(32));

    verifyNever(() => bridge.replaceCache(any()));
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
