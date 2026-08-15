import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_vault_key_context_store.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Keys extends Mock implements VaultRotationCryptoService {}

class _Sync extends Mock implements MemberSyncCoordinator {}

void main() {
  late _Vaults vaults;
  late _Keys keys;
  late _Sync sync;
  late MemberVaultKeyContextStore contexts;
  late MemberEntryListService service;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    vaults = _Vaults();
    keys = _Keys();
    sync = _Sync();
    contexts = MemberVaultKeyContextStore();
    service = MemberEntryListService(
      vaults: vaults,
      keys: keys,
      sync: sync,
      keyContexts: contexts,
    );
    when(
      () => keys.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32));
    when(() => sync.entries(any())).thenReturn(const []);
  });

  test(
    'uses authenticated list key context without a vault detail GET',
    () async {
      contexts.install(
        vaultId: 'vault',
        memberVaultKey: const {'encodedSuitePayload': 'ciphertext'},
        memberKeyGeneration: 3,
      );
      when(
        () => sync.synchronize(
          vaultId: 'vault',
          vaultKey: any(named: 'vaultKey'),
          minimumMemberKeyGeneration: 3,
        ),
      ).thenAnswer(
        (_) async => const MemberSyncResult(
          sequence: '1',
          entryCount: 0,
          usedSnapshot: false,
        ),
      );

      await service.load(vaultId: 'vault', memberPrivateKey: Uint8List(32));

      verifyNever(() => vaults.getMemberVaultKeyContext(any()));
      verify(
        () => sync.synchronize(
          vaultId: 'vault',
          vaultKey: any(named: 'vaultKey'),
          minimumMemberKeyGeneration: 3,
        ),
      ).called(1);
    },
  );

  test(
    'concurrent loads for one vault share the complete sync operation',
    () async {
      contexts.install(
        vaultId: 'vault',
        memberVaultKey: const {'encodedSuitePayload': 'ciphertext'},
        memberKeyGeneration: 1,
      );
      final pending = Completer<MemberSyncResult>();
      when(
        () => sync.synchronize(
          vaultId: 'vault',
          vaultKey: any(named: 'vaultKey'),
          minimumMemberKeyGeneration: 1,
        ),
      ).thenAnswer((_) => pending.future);

      final first = service.load(
        vaultId: 'vault',
        memberPrivateKey: Uint8List(32),
      );
      final second = service.load(
        vaultId: 'vault',
        memberPrivateKey: Uint8List(32),
      );

      expect(identical(first, second), isTrue);
      pending.complete(
        const MemberSyncResult(
          sequence: '1',
          entryCount: 0,
          usedSnapshot: false,
        ),
      );
      await Future.wait([first, second]);

      verify(
        () => sync.synchronize(
          vaultId: 'vault',
          vaultKey: any(named: 'vaultKey'),
          minimumMemberKeyGeneration: 1,
        ),
      ).called(1);
    },
  );

  test('fallback detail context is cached for later loads', () async {
    when(() => vaults.getMemberVaultKeyContext('vault')).thenAnswer(
      (_) async => {
        'memberVaultKey': <String, dynamic>{
          'encodedSuitePayload': 'ciphertext',
        },
        'memberKeyGeneration': 2,
      },
    );
    when(
      () => sync.synchronize(
        vaultId: 'vault',
        vaultKey: any(named: 'vaultKey'),
        minimumMemberKeyGeneration: 2,
      ),
    ).thenAnswer(
      (_) async => const MemberSyncResult(
        sequence: '1',
        entryCount: 0,
        usedSnapshot: false,
      ),
    );

    await service.load(vaultId: 'vault', memberPrivateKey: Uint8List(32));
    await service.load(vaultId: 'vault', memberPrivateKey: Uint8List(32));

    verify(() => vaults.getMemberVaultKeyContext('vault')).called(1);
  });

  test(
    'refreshes stale cached key context once before retrying member sync',
    () async {
      contexts.install(
        vaultId: 'vault',
        memberVaultKey: const {'encodedSuitePayload': 'old-ciphertext'},
        memberKeyGeneration: 1,
      );
      when(() => vaults.getMemberVaultKeyContext('vault')).thenAnswer(
        (_) async => {
          'memberVaultKey': <String, dynamic>{
            'encodedSuitePayload': 'new-ciphertext',
          },
          'memberKeyGeneration': 2,
        },
      );
      when(
        () => sync.synchronize(
          vaultId: 'vault',
          vaultKey: any(named: 'vaultKey'),
          minimumMemberKeyGeneration: 1,
        ),
      ).thenThrow(
        const MemberVaultKeyContextStaleException(requiredGeneration: 2),
      );
      when(
        () => sync.synchronize(
          vaultId: 'vault',
          vaultKey: any(named: 'vaultKey'),
          minimumMemberKeyGeneration: 2,
        ),
      ).thenAnswer(
        (_) async => const MemberSyncResult(
          sequence: '2',
          entryCount: 0,
          usedSnapshot: false,
        ),
      );

      await service.load(vaultId: 'vault', memberPrivateKey: Uint8List(32));

      verify(() => vaults.getMemberVaultKeyContext('vault')).called(1);
      verify(
        () => sync.synchronize(
          vaultId: 'vault',
          vaultKey: any(named: 'vaultKey'),
          minimumMemberKeyGeneration: 1,
        ),
      ).called(1);
      verify(
        () => sync.synchronize(
          vaultId: 'vault',
          vaultKey: any(named: 'vaultKey'),
          minimumMemberKeyGeneration: 2,
        ),
      ).called(1);
    },
  );
}
