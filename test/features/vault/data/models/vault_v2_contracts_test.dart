import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/models/vault_v2_contracts.dart';

void main() {
  test('Vault public keys use exact closed backend kinds', () {
    const messageKey = VaultPublicKeyContractModel(
      schemeId: 'x25519',
      keyKind: VaultPublicKeyKind.agentMessageX25519,
      keyVersion: 1,
      encodedPublicKey: 'key',
      fingerprint: 'fingerprint',
    );
    const signingKey = VaultPublicKeyContractModel(
      schemeId: 'ed25519',
      keyKind: VaultPublicKeyKind.manifestSigningEd25519,
      keyVersion: 1,
      encodedPublicKey: 'key',
      fingerprint: 'fingerprint',
    );

    expect(messageKey.toJson()['keyKind'], 1);
    expect(signingKey.toJson()['keyKind'], 2);
  });

  test('create request contains only canonical encrypted contract roots', () {
    const envelope = VaultOpaqueEnvelopeModel(
      descriptor: {'protocolVersion': 2},
      encodedSuitePayload: 'opaque',
    );
    const wrapper = X25519WrappedKeyModel(
      descriptor: X25519WrapperDescriptorModel(
        wrapperSuiteId: 'palladin-x25519-sealed-box-v1',
        purpose: 1,
        scope: {'organizationId': 'org', 'vaultId': 'vault'},
        resourceRevision: '1',
        wrappedKeyVersion: 1,
        memberKeyGeneration: 1,
        recipientKeyKind: 5,
        recipientKeyVersion: 1,
        recipientFingerprint: 'fingerprint',
      ),
      encodedSealedKeyPackage: 'opaque',
    );
    const publicKey = VaultPublicKeyContractModel(
      schemeId: 'x25519',
      keyKind: VaultPublicKeyKind.agentMessageX25519,
      keyVersion: 1,
      encodedPublicKey: 'key',
      fingerprint: 'fingerprint',
    );
    const request = CreateVaultV2Request(
      vaultId: 'vault',
      memberVaultMetadata: envelope,
      currentKeyEpoch: VaultKeyEpochModel(
        vaultKeyVersion: 1,
        vdkVersion: 1,
        agentMessageKeyVersion: 1,
        manifestSigningKeyVersion: 1,
      ),
      creatorVaultKey: wrapper,
      discoveryKey: envelope,
      vaultPrivateKeys: [envelope, envelope],
      vaultAgentMessagePublicKey: publicKey,
      vaultManifestSigningPublicKey: publicKey,
    );

    final json = request.toJson();
    expect(json, isNot(contains('name')));
    expect(json, isNot(contains('wrappedVK')));
    expect(
      json.keys,
      containsAll(<String>[
        'memberVaultMetadata',
        'creatorVaultKey',
        'discoveryKey',
        'vaultPrivateKeys',
        'vaultAgentMessagePublicKey',
        'vaultManifestSigningPublicKey',
      ]),
    );
  });
}
