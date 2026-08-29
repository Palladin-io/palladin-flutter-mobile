import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';
import 'package:mobile_palladin/features/vault/data/services/member_vault_key_context_store.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';

class _MockVaultRemote extends Mock implements VaultRemoteDatasource {}

class _MockVaultKeys extends Mock implements VaultRotationCryptoService {}

class _MockSync extends Mock implements MemberSyncCoordinator {}

class _MockAuthorityProvider extends Mock
    implements MemberSyncSessionAuthorityProvider {}

void main() {
  late _MockVaultKeys keys;
  late _MockSync sync;
  late _MockAuthorityProvider authorityProvider;
  late MemberEntryListService service;
  late MemberVaultKeyContextStore contexts;

  const vaultId = '22222222-2222-4222-8222-222222222222';
  const authority = MemberSyncSessionAuthority(
    principalId: '44444444-4444-4444-8444-444444444444',
    organizationId: '11111111-1111-4111-8111-111111111111',
    organizationMembershipGeneration: '7',
    offlinePolicy: '24h',
    offlinePolicyVersion: 1,
  );
  final wrapper = <String, dynamic>{
    'wrappedVaultKey': {
      'descriptor': {'memberKeyGeneration': 4},
      'encodedSealedKeyPackage': 'ciphertext',
    },
  };

  setUpAll(() {
    registerFallbackValue(authority);
    registerFallbackValue(Uint8List(32));
  });

  setUp(() {
    keys = _MockVaultKeys();
    sync = _MockSync();
    authorityProvider = _MockAuthorityProvider();
    contexts = MemberVaultKeyContextStore()
      ..install(
        vaultId: vaultId,
        memberVaultKey: wrapper,
        memberKeyGeneration: 4,
      );
    when(authorityProvider.current).thenAnswer((_) async => authority);
    when(
      () => keys.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => sync.synchronize(
        vaultId: any(named: 'vaultId'),
        vaultKey: any(named: 'vaultKey'),
        minimumMemberKeyGeneration: any(named: 'minimumMemberKeyGeneration'),
        authority: any(named: 'authority'),
        authoritativeMemberVaultKey: any(named: 'authoritativeMemberVaultKey'),
      ),
    ).thenAnswer(
      (_) async => const MemberSyncResult(
        sequence: '12',
        entryCount: 0,
        usedSnapshot: true,
      ),
    );
    when(() => sync.entries(vaultId)).thenReturn(const []);
    service = MemberEntryListService(
      vaults: _MockVaultRemote(),
      keys: keys,
      sync: sync,
      authorityProvider: authorityProvider,
      keyContexts: contexts,
    );
  });

  test(
    'passes independent session and Vault wrapper authority to sync',
    () async {
      await service.load(vaultId: vaultId, memberPrivateKey: Uint8List(32));

      verify(
        () => sync.synchronize(
          vaultId: vaultId,
          vaultKey: any(named: 'vaultKey'),
          minimumMemberKeyGeneration: 4,
          authority: authority,
          authoritativeMemberVaultKey: wrapper,
        ),
      ).called(1);
    },
  );

  test('concurrent consumers share one combined sync request', () async {
    final first = service.load(
      vaultId: vaultId,
      memberPrivateKey: Uint8List(32),
    );
    final second = service.load(
      vaultId: vaultId,
      memberPrivateKey: Uint8List(32),
    );

    await Future.wait([first, second]);

    verify(
      () => sync.synchronize(
        vaultId: vaultId,
        vaultKey: any(named: 'vaultKey'),
        minimumMemberKeyGeneration: 4,
        authority: authority,
        authoritativeMemberVaultKey: wrapper,
      ),
    ).called(1);
  });

  test('lock clears process-memory Vault wrapper context', () {
    service.lock();

    expect(contexts.get(vaultId), isNull);
    verify(sync.lock).called(1);
  });
}
