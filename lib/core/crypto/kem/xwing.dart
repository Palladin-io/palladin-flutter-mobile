import 'dart:typed_data';

import 'package:pointycastle/digests/sha3.dart';
import 'package:pointycastle/digests/shake.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import 'ml_kem_768.dart';

/// X-Wing KEM, draft-connolly-cfrg-xwing-kem-10 (ML-KEM-768 + X25519).
///
/// The decapsulation key is the 32-byte seed; the expanded key is rebuilt on
/// every use and wiped afterwards, never stored.
final class XWing {
  XWing(this._sodium);

  static const seedBytes = 32;
  static const publicKeyBytes = 1216;
  static const ciphertextBytes = 1120;
  static const sharedSecretBytes = 32;
  static const encapsulationRandomnessBytes = 64;

  static final Uint8List _label = Uint8List.fromList([
    0x5c,
    0x2e,
    0x2f,
    0x2f,
    0x5e,
    0x5c,
  ]);

  final SodiumSumo _sodium;

  Uint8List generateSeed() => _sodium.randombytes.buf(seedBytes);

  Uint8List publicKeyFromSeed(Uint8List seed) {
    final expanded = _expand(seed);
    try {
      return expanded.publicKey;
    } finally {
      expanded.dispose();
    }
  }

  /// Encapsulates with CSPRNG randomness; returns `(sharedSecret, ciphertext)`.
  (Uint8List, Uint8List) encapsulate(Uint8List publicKey) {
    final randomness = _sodium.randombytes.buf(encapsulationRandomnessBytes);
    try {
      return encapsulateDerandomized(publicKey, randomness);
    } finally {
      randomness.fillRange(0, randomness.length, 0);
    }
  }

  /// Deterministic encapsulation, used directly only by known-answer tests.
  (Uint8List, Uint8List) encapsulateDerandomized(
    Uint8List publicKey,
    Uint8List randomness,
  ) {
    if (publicKey.length != publicKeyBytes ||
        randomness.length != encapsulationRandomnessBytes) {
      throw ArgumentError('X-Wing encapsulation input length');
    }
    final pkM = Uint8List.sublistView(publicKey, 0, 1184);
    final pkX = Uint8List.sublistView(publicKey, 1184);
    final ephemeral = SecureKey.fromList(
      _sodium,
      Uint8List.sublistView(randomness, 32, 64),
    );
    SecureKey? sharedX;
    Uint8List? ssX;
    Uint8List? ssM;
    try {
      final ctX = _sodium.crypto.scalarmult.base(n: ephemeral);
      sharedX = _scalarmult(ephemeral, pkX);
      ssX = sharedX.extractBytes();
      final (mlKemSecret, ctM) = MlKem768.encapsulateInternal(
        Uint8List.fromList(pkM),
        Uint8List.fromList(randomness.sublist(0, 32)),
      );
      ssM = mlKemSecret;
      final ciphertext = Uint8List(ciphertextBytes)
        ..setRange(0, 1088, ctM)
        ..setRange(1088, ciphertextBytes, ctX);
      return (_combine(ssM, ssX, ctX, pkX), ciphertext);
    } finally {
      ephemeral.dispose();
      sharedX?.dispose();
      ssX?.fillRange(0, ssX.length, 0);
      ssM?.fillRange(0, ssM.length, 0);
    }
  }

  Uint8List decapsulate(Uint8List ciphertext, Uint8List seed) {
    if (ciphertext.length != ciphertextBytes || seed.length != seedBytes) {
      throw ArgumentError('X-Wing decapsulation input length');
    }
    final expanded = _expand(seed);
    final ctX = Uint8List.sublistView(ciphertext, 1088);
    SecureKey? sharedX;
    Uint8List? ssX;
    Uint8List? ssM;
    try {
      ssM = MlKem768.decapsulate(
        expanded.decapsulationKey,
        Uint8List.fromList(ciphertext.sublist(0, 1088)),
      );
      sharedX = _scalarmult(expanded.x25519Secret, ctX);
      ssX = sharedX.extractBytes();
      return _combine(ssM, ssX, ctX, expanded.x25519Public);
    } finally {
      expanded.dispose();
      sharedX?.dispose();
      ssX?.fillRange(0, ssX.length, 0);
      ssM?.fillRange(0, ssM.length, 0);
    }
  }

  SecureKey _scalarmult(SecureKey secret, Uint8List publicKey) {
    try {
      return _sodium.crypto.scalarmult(n: secret, p: publicKey);
    } on SodiumException {
      // libsodium rejects low-order points (all-zero shared secret).
      throw ArgumentError('X-Wing X25519 point');
    }
  }

  _ExpandedKey _expand(Uint8List seed) {
    if (seed.length != seedBytes) throw ArgumentError('X-Wing seed length');
    final expanded = Uint8List(96);
    SHAKEDigest(256)
      ..update(seed, 0, seed.length)
      ..doFinalRange(expanded, 0, 96);
    try {
      final (ekM, dkM) = MlKem768.keyGenInternal(
        Uint8List.fromList(expanded.sublist(0, 32)),
        Uint8List.fromList(expanded.sublist(32, 64)),
      );
      final x25519Secret = SecureKey.fromList(
        _sodium,
        Uint8List.sublistView(expanded, 64, 96),
      );
      return _ExpandedKey(
        decapsulationKey: dkM,
        encapsulationKey: ekM,
        x25519Secret: x25519Secret,
        x25519Public: _sodium.crypto.scalarmult.base(n: x25519Secret),
      );
    } finally {
      expanded.fillRange(0, expanded.length, 0);
    }
  }

  static Uint8List _combine(
    Uint8List ssM,
    Uint8List ssX,
    Uint8List ctX,
    Uint8List pkX,
  ) {
    final digest = SHA3Digest(256)
      ..update(ssM, 0, ssM.length)
      ..update(ssX, 0, ssX.length)
      ..update(ctX, 0, ctX.length)
      ..update(pkX, 0, pkX.length)
      ..update(_label, 0, _label.length);
    final out = Uint8List(sharedSecretBytes);
    digest.doFinal(out, 0);
    return out;
  }
}

final class _ExpandedKey {
  _ExpandedKey({
    required this.decapsulationKey,
    required this.encapsulationKey,
    required this.x25519Secret,
    required this.x25519Public,
  });

  final Uint8List decapsulationKey;
  final Uint8List encapsulationKey;
  final SecureKey x25519Secret;
  final Uint8List x25519Public;

  Uint8List get publicKey => Uint8List(XWing.publicKeyBytes)
    ..setRange(0, 1184, encapsulationKey)
    ..setRange(1184, XWing.publicKeyBytes, x25519Public);

  void dispose() {
    decapsulationKey.fillRange(0, decapsulationKey.length, 0);
    x25519Secret.dispose();
  }
}
