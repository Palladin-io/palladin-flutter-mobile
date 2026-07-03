import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';

/// Zero-knowledge crypto pipeline for vault creation.
///
/// Generates a fresh 32-byte vault key (VK) and seals it for the
/// user's X25519 public key using `crypto_box_seal` (anonymous sealed
/// box). The wrapped VK is base64-encoded and shipped to the backend
/// — the plaintext VK never leaves this method's stack frame.
///
/// The owner derives their own public key from [privateKey] via
/// `crypto_scalarmult_base`, so the caller only needs to supply the
/// private key already cached in the unlocked auth state.
class VaultCryptoService {
  VaultCryptoService({Future<SodiumSumo> Function()? sodiumLoader})
      : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Generates a random 32-byte vault key, derives the user's X25519
  /// public key from [privateKey], seals the VK for that public key,
  /// and returns the sealed bytes base64-encoded.
  ///
  /// The plaintext VK and any intermediate [SecureKey] handles are
  /// disposed before returning — only the sealed copy survives this
  /// call.
  Future<String> generateWrappedVK(Uint8List privateKey) async {
    final sodium = await _sodiumLoader();

    final vk = sodium.randombytes.buf(32);
    final scalar = SecureKey.fromList(sodium, privateKey);
    try {
      final publicKey = sodium.crypto.scalarmult.base(n: scalar);

      final wrapped = sodium.crypto.box.seal(
        message: vk,
        publicKey: publicKey,
      );

      return base64.encode(wrapped);
    } finally {
      // Zeroize the plaintext VK and the SecureKey copy of the
      // private key — the wrapped copy is the only thing that should
      // survive this method.
      vk.fillRange(0, vk.length, 0);
      scalar.dispose();
    }
  }

  /// Generates a random 32-byte vault key, seals it directly for the
  /// supplied X25519 [publicKey], and returns the sealed bytes
  /// base64-encoded.
  ///
  /// Use this variant when the private key is unavailable (e.g. during
  /// the onboarding flow where the keypair is generated, used to build
  /// the setup payload, and then zeroed before this call). The public
  /// key from [OnboardingSetupPayload.publicKey] is passed directly so
  /// no private-key material is needed.
  ///
  /// The plaintext VK is zeroized before returning.
  Future<String> generateWrappedVKFromPublicKey(Uint8List publicKey) async {
    final sodium = await _sodiumLoader();
    final vk = sodium.randombytes.buf(32);
    try {
      final wrapped = sodium.crypto.box.seal(
        message: vk,
        publicKey: publicKey,
      );
      return base64.encode(wrapped);
    } finally {
      vk.fillRange(0, vk.length, 0);
    }
  }
}
