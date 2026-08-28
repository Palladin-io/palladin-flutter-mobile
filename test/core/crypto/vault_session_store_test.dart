import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';

void main() {
  const organizationId = 'organization-id';
  const vaultId = 'vault-id';
  const epoch = VaultKeyEpoch(
    vaultKeyVersion: 1,
    vdkVersion: 1,
    agentMessageKeyVersion: 1,
    manifestSigningKeyVersion: 1,
  );
  const wrapper = MemberVaultKeyWrapperMetadata(
    wrapperSuiteId: 'palladin-x25519-sealedbox-v1',
    wrappedKeyVersion: 1,
    memberKeyGeneration: 1,
    recipientKeyVersion: 1,
    recipientFingerprint: 'fingerprint',
  );

  test('clear wipes every unlocked Vault session', () {
    final store = VaultSessionStore();
    store.install(
      organizationId: organizationId,
      vaultId: vaultId,
      vaultKey: Uint8List.fromList(List<int>.filled(32, 7)),
      epoch: epoch,
      memberKeyGeneration: 1,
      wrapper: wrapper,
    );

    store.clear();

    expect(store.unlockedVaultIds, isEmpty);
    expect(
      () =>
          store.copyVaultKey(organizationId: organizationId, vaultId: vaultId),
      throwsStateError,
    );
  });

  test('Member key replacement and clear advance the session generation', () {
    final store = VaultSessionStore();
    final initialGeneration = store.memberKeySessionGeneration;

    store.setMemberPrivateKey(Uint8List(32));
    expect(store.memberKeySessionGeneration, initialGeneration + 1);

    store.setMemberPrivateKey(Uint8List.fromList(List<int>.filled(32, 7)));
    expect(store.memberKeySessionGeneration, initialGeneration + 2);

    store.clear();
    expect(store.memberKeySessionGeneration, initialGeneration + 3);
  });

  test('failed replacement leaves the previous session intact', () {
    final store = VaultSessionStore();
    final originalKey = Uint8List.fromList(List<int>.filled(32, 7));
    store.install(
      organizationId: organizationId,
      vaultId: vaultId,
      vaultKey: originalKey,
      epoch: epoch,
      memberKeyGeneration: 1,
      wrapper: wrapper,
    );

    expect(
      () => store.install(
        organizationId: organizationId,
        vaultId: vaultId,
        vaultKey: Uint8List(31),
        epoch: epoch,
        memberKeyGeneration: 1,
        wrapper: wrapper,
      ),
      throwsArgumentError,
    );

    expect(
      store.copyVaultKey(organizationId: organizationId, vaultId: vaultId),
      originalKey,
    );
  });

  test('returned keys are defensive copies', () {
    final store = VaultSessionStore();
    final discoveryKey = Uint8List.fromList(List<int>.filled(32, 9));
    store.install(
      organizationId: organizationId,
      vaultId: vaultId,
      vaultKey: Uint8List.fromList(List<int>.filled(32, 7)),
      vaultDiscoveryKey: discoveryKey,
      epoch: epoch,
      memberKeyGeneration: 1,
      wrapper: wrapper,
    );

    final mutatedCopy = store.copyVaultKey(
      organizationId: organizationId,
      vaultId: vaultId,
    );
    mutatedCopy.fillRange(0, 32, 0);
    final mutatedDiscoveryCopy = store.copyVaultDiscoveryKey(
      organizationId: organizationId,
      vaultId: vaultId,
    );
    mutatedDiscoveryCopy.fillRange(0, 32, 0);

    expect(
      store.copyVaultKey(organizationId: organizationId, vaultId: vaultId),
      everyElement(7),
    );
    expect(
      store.copyVaultDiscoveryKey(
        organizationId: organizationId,
        vaultId: vaultId,
      ),
      everyElement(9),
    );
  });
}
