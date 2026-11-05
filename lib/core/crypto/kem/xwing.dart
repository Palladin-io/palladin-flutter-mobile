import 'dart:ffi';
import 'dart:typed_data';

import 'package:sodium/sodium.ffi.dart';
import 'package:sodium/sodium_sumo.dart';

/// X-Wing KEM, draft-connolly-cfrg-xwing-kem-10 (ML-KEM-768 + X25519), from
/// libsodium's audited `crypto_kem_xwing`.
///
/// The decapsulation key is the 32-byte seed; libsodium expands it on every
/// use, so the expanded key is never held by Dart.
final class XWing {
  XWing(this._sodium) {
    final kem = _sodium.crypto.kem;
    if (kem.primitive != 'xwing' ||
        kem.seedBytes != seedBytes ||
        kem.secretKeyBytes != seedBytes ||
        kem.publicKeyBytes != publicKeyBytes ||
        kem.ciphertextBytes != ciphertextBytes ||
        kem.sharedSecretBytes != sharedSecretBytes) {
      throw StateError('libsodium crypto_kem is not X-Wing');
    }
  }

  static const seedBytes = 32;
  static const publicKeyBytes = 1216;
  static const ciphertextBytes = 1120;
  static const sharedSecretBytes = 32;
  static const encapsulationRandomnessBytes = 64;

  final SodiumSumo _sodium;

  Uint8List generateSeed() => _sodium.randombytes.buf(seedBytes);

  Uint8List publicKeyFromSeed(Uint8List seed) {
    if (seed.length != seedBytes) throw ArgumentError('X-Wing seed length');
    final secureSeed = SecureKey.fromList(_sodium, seed);
    try {
      final pair = _sodium.crypto.kem.seedKeyPair(secureSeed);
      pair.secretKey.dispose();
      return pair.publicKey;
    } finally {
      secureSeed.dispose();
    }
  }

  /// Encapsulates with libsodium's CSPRNG; returns `(sharedSecret, ciphertext)`.
  (Uint8List, Uint8List) encapsulate(Uint8List publicKey) {
    _checkPublicKey(publicKey);
    final result = _guard(() => _sodium.crypto.kem.enc(publicKey: publicKey));
    try {
      return (result.sharedSecret.extractBytes(), result.ciphertext);
    } finally {
      result.sharedSecret.dispose();
    }
  }

  /// Deterministic encapsulation, used directly only by known-answer tests.
  (Uint8List, Uint8List) encapsulateDerandomized(
    Uint8List publicKey,
    Uint8List randomness,
  ) {
    _checkPublicKey(publicKey);
    if (randomness.length != encapsulationRandomnessBytes) {
      throw ArgumentError('X-Wing encapsulation input length');
    }
    const ffi = LibSodiumFFI();
    final ciphertext = SodiumPointer<UnsignedChar>.alloc(
      ffi,
      count: ciphertextBytes,
    );
    final sharedSecret = SodiumPointer<UnsignedChar>.alloc(
      ffi,
      count: sharedSecretBytes,
    );
    final key = publicKey.toSodiumPointer<UnsignedChar>(
      ffi,
      memoryProtection: MemoryProtection.readOnly,
    );
    final seed = randomness.toSodiumPointer<UnsignedChar>(
      ffi,
      memoryProtection: MemoryProtection.readOnly,
    );
    try {
      final status = ffi.crypto_kem_xwing_enc_deterministic(
        ciphertext.ptr,
        sharedSecret.ptr,
        key.ptr,
        seed.ptr,
      );
      if (status != 0) throw ArgumentError('X-Wing encapsulation failed');
      return (
        Uint8List.fromList(sharedSecret.asListView<Uint8List>()),
        Uint8List.fromList(ciphertext.asListView<Uint8List>()),
      );
    } finally {
      ciphertext.dispose();
      sharedSecret.dispose();
      key.dispose();
      seed.dispose();
    }
  }

  Uint8List decapsulate(Uint8List ciphertext, Uint8List seed) {
    if (ciphertext.length != ciphertextBytes || seed.length != seedBytes) {
      throw ArgumentError('X-Wing decapsulation input length');
    }
    final secretKey = SecureKey.fromList(_sodium, seed);
    try {
      final sharedSecret = _guard(
        () => _sodium.crypto.kem.dec(
          ciphertext: ciphertext,
          secretKey: secretKey,
        ),
      );
      try {
        return sharedSecret.extractBytes();
      } finally {
        sharedSecret.dispose();
      }
    } finally {
      secretKey.dispose();
    }
  }

  static void _checkPublicKey(Uint8List publicKey) {
    if (publicKey.length != publicKeyBytes) {
      throw ArgumentError('X-Wing encapsulation input length');
    }
  }

  static T _guard<T>(T Function() call) {
    try {
      return call();
    } on SodiumException {
      // libsodium rejects a malformed encapsulation key or a low-order
      // X25519 point; callers map ArgumentError to their own failure kind.
      throw ArgumentError('X-Wing key material');
    }
  }
}
