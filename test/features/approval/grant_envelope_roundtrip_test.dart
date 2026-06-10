import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/features/approval/data/services/grant_crypto_service.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

/// End-to-end byte-compatibility test for the grant envelope.
///
/// Produces the envelope exactly as [GrantCryptoService] does on approval,
/// then plays the role of the **MCP consumer** to verify it can recover
/// the plaintext:
///   1. `DEK   = crypto_box_seal_open(agent_secret_key, agentWrappedDek)`
///   2. `plain = crypto_secretbox_open(DEK, reEncryptedBlob, nonce)`
///
/// This is the contract the spec (Security Model) mandates between the
/// owner client (Flutter, producer) and the agent (MCP, consumer). If the
/// algorithms or encodings drift, this test fails.
///
/// libsodium must be loadable in the test host. In a pure-Dart `flutter
/// test` VM the `sodium_libs` platform channel is unavailable, so the
/// test self-skips with a clear reason rather than failing CI. It runs in
/// full on a device / integration host.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;
  var sodiumAvailable = false;

  setUpAll(() async {
    try {
      sodium = await SodiumSumoInit.init();
      sodiumAvailable = true;
    } catch (_) {
      sodiumAvailable = false;
    }
  });

  test('envelope round-trips to the original plaintext (producer↔consumer)',
      () async {
    if (!sodiumAvailable) {
      markTestSkipped('libsodium not loadable in this test host');
      return;
    }

    // --- Fixture: owner keypair, vault key, agent keypair --------------
    final ownerKeypair = sodium.crypto.box.keyPair();
    final agentKeypair = sodium.crypto.box.keyPair();

    // Vault Key (symmetric, 32 bytes), sealed to the owner's public key —
    // exactly how the backend stores wrapped_VK.
    final vk = sodium.crypto.secretBox.keygen();
    final vkBytes = vk.extractBytes();
    final wrappedVK = base64.encode(
      sodium.crypto.box.seal(
        message: vkBytes,
        publicKey: ownerKeypair.publicKey,
      ),
    );

    // The entry, encrypted with the VK (what the entry detail endpoint
    // returns).
    final plaintext = utf8.encode(
      '{"username":"alice","password":"s3cr3t-üñ"}',
    );
    final entryNonce = sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
    final entryBlob = sodium.crypto.secretBox.easy(
      message: Uint8List.fromList(plaintext),
      nonce: entryNonce,
      key: vk,
    );

    // --- Produce the envelope (owner-side, the code under test) --------
    final service = GrantCryptoService();
    final ownerPriv = ownerKeypair.secretKey.extractBytes();
    final envelope = await service.produceGrantEnvelope(
      wrappedVK: wrappedVK,
      privateKey: ownerPriv,
      entryBlob: base64.encode(entryBlob),
      entryNonce: base64.encode(entryNonce),
      agentPublicKey: base64.encode(agentKeypair.publicKey),
    );

    // --- Consume the envelope (agent-side / MCP simulation) ------------
    final dek = sodium.crypto.box.sealOpen(
      cipherText: base64.decode(envelope.agentWrappedDek),
      publicKey: agentKeypair.publicKey,
      secretKey: agentKeypair.secretKey,
    );
    final recovered = sodium.crypto.secretBox.openEasy(
      cipherText: base64.decode(envelope.reEncryptedBlob),
      nonce: base64.decode(envelope.nonce),
      key: SecureKey.fromList(sodium, dek),
    );

    expect(recovered, equals(plaintext));
    // The re-encrypted blob must NOT be the original (fresh DEK + nonce).
    expect(base64.decode(envelope.reEncryptedBlob), isNot(equals(entryBlob)));
  });
}
