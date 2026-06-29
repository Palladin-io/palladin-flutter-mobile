import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/exceptions/approval_exceptions.dart';

/// Zero-knowledge crypto pipeline for **producing a grant envelope** when
/// the vault owner approves an agent's request.
///
/// Implements exactly the GRANULAR approval scheme from
/// `brain/Technical/Security Model.md`:
///
/// 1. `VK = crypto_box_seal_open(user_private_key, wrapped_VK)`
/// 2. `plaintext = crypto_secretbox_open(VK, entry.blob, entry.nonce)`
/// 3. `DEK = random 32 bytes`
/// 4. `re_blob = crypto_secretbox(DEK, plaintext, new_nonce)`
/// 5. `agent_wrapped_DEK = crypto_box_seal(agent_public_key, DEK)`
///
/// Algorithms (libsodium, byte-compatible with the MCP consumer which
/// runs `crypto_box_seal_open` + `crypto_secretbox_open`):
///   * `crypto_secretbox`  → XSalsa20-Poly1305
///   * `crypto_box_seal`    → X25519 sealed box
///
/// Every secret buffer (VK, plaintext, DEK) is zeroed in a `finally`
/// block before this method returns. No secret material is ever logged.
class GrantCryptoService {
  GrantCryptoService({Future<SodiumSumo> Function()? sodiumLoader})
      : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Produces the grant envelope for a single entry.
  ///
  /// Inputs:
  ///   * [wrappedVK]      — base64 sealed Vault Key (sealed to the owner's
  ///                        public key); from the loaded vault detail.
  ///   * [privateKey]     — owner's X25519 private key from the unlocked
  ///                        in-memory auth state. Never persisted.
  ///   * [entryBlob]      — base64 `crypto_secretbox` ciphertext of the
  ///                        entry (encrypted with VK).
  ///   * [entryNonce]     — base64 24-byte nonce for [entryBlob].
  ///   * [agentPublicKey] — base64 X25519 public key of the requesting
  ///                        agent (`Agent.PublicKey`).
  ///
  /// Returns a [GrantEnvelope] carrying the re-encrypted blob, its fresh
  /// nonce, and the agent-sealed DEK — all base64, ready to PUT to the
  /// approve endpoint.
  ///
  /// Throws [ApprovalException] with [ApprovalErrorKind.cryptoFailure] on
  /// any libsodium failure (bad VK, tampered blob, malformed agent key).
  Future<GrantEnvelope> produceGrantEnvelope({
    required String wrappedVK,
    required Uint8List privateKey,
    required String entryBlob,
    required String entryNonce,
    required String agentPublicKey,
  }) async {
    final sodium = await _sodiumLoader();
    final scalar = SecureKey.fromList(sodium, privateKey);

    Uint8List? vaultKey;
    Uint8List? plaintext;
    Uint8List? dek;
    SecureKey? dekKey;

    try {
      // 1. Unwrap VK with the owner's keypair (sealed box open).
      final ownerPublic = sodium.crypto.scalarmult.base(n: scalar);
      try {
        vaultKey = sodium.crypto.box.sealOpen(
          cipherText: base64.decode(wrappedVK),
          publicKey: ownerPublic,
          secretKey: scalar,
        );
      } on SodiumException catch (e, s) {
        AppLogger.w('Approval', 'VK unwrap failed: ${e.runtimeType}');
        AppLogger.e('Approval', 'sealOpen(VK) failed', error: e, stackTrace: s);
        throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
      }

      // 2. Decrypt the entry with VK.
      final vkSecret = SecureKey.fromList(sodium, vaultKey);
      try {
        plaintext = sodium.crypto.secretBox.openEasy(
          cipherText: base64.decode(entryBlob),
          nonce: base64.decode(entryNonce),
          key: vkSecret,
        );
      } on SodiumException catch (e, s) {
        AppLogger.w('Approval', 'entry decrypt failed');
        AppLogger.e('Approval', 'openEasy(entry) failed',
            error: e, stackTrace: s);
        throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
      } finally {
        vkSecret.dispose();
      }

      // 3. Fresh per-grant DEK.
      dek = sodium.randombytes.buf(sodium.crypto.secretBox.keyBytes);
      dekKey = SecureKey.fromList(sodium, dek);

      // 4. Re-encrypt the plaintext with the DEK under a new nonce.
      final newNonce =
          sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
      final reBlob = sodium.crypto.secretBox.easy(
        message: plaintext,
        nonce: newNonce,
        key: dekKey,
      );

      // 5. Seal the DEK to the agent's public key.
      final Uint8List agentWrappedDek;
      try {
        agentWrappedDek = sodium.crypto.box.seal(
          message: dek,
          publicKey: base64.decode(agentPublicKey),
        );
      } on SodiumException catch (e, s) {
        AppLogger.w('Approval', 'DEK seal failed');
        AppLogger.e('Approval', 'seal(DEK) failed', error: e, stackTrace: s);
        throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
      }

      return GrantEnvelope(
        reEncryptedBlob: base64.encode(reBlob),
        nonce: base64.encode(newNonce),
        agentWrappedDek: base64.encode(agentWrappedDek),
      );
    } finally {
      // Zero every secret buffer we held, regardless of outcome.
      scalar.dispose();
      dekKey?.dispose();
      if (vaultKey != null) vaultKey.fillRange(0, vaultKey.length, 0);
      if (plaintext != null) plaintext.fillRange(0, plaintext.length, 0);
      if (dek != null) dek.fillRange(0, dek.length, 0);
    }
  }
}

/// The product of [GrantCryptoService.produceGrantEnvelope] — all base64,
/// carries no live key material (the DEK lives only sealed to the agent).
class GrantEnvelope {
  const GrantEnvelope({
    required this.reEncryptedBlob,
    required this.nonce,
    required this.agentWrappedDek,
  });

  /// Base64 `crypto_secretbox` ciphertext, encrypted with the per-grant
  /// DEK.
  final String reEncryptedBlob;

  /// Base64 24-byte nonce for [reEncryptedBlob].
  final String nonce;

  /// Base64 `crypto_box_seal` of the DEK to the agent's public key.
  final String agentWrappedDek;
}
