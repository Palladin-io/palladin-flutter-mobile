import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/kem/xwing.dart';

import '../../support/native_sodium.dart';

void main() {
  final kat =
      readJsonFixture(
            'test/fixtures/key-wrapper-v1/vectors.json',
          )['xwingKnownAnswer']
          as Map<String, dynamic>;
  late XWing xwing;

  setUpAll(() async => xwing = XWing(await loadTestSodium()));

  test('matches the draft-10 known-answer vector', () {
    final seed = hexBytes(kat['seedHex'] as String);
    final publicKey = xwing.publicKeyFromSeed(seed);
    expect(publicKey.length, XWing.publicKeyBytes);
    expect(toHex(publicKey.sublist(0, 16)), kat['publicKeyPrefixHex']);
    expect(toHex(sha256.convert(publicKey).bytes), kat['publicKeySha256Hex']);

    final (sharedSecret, ciphertext) = xwing.encapsulateDerandomized(
      publicKey,
      hexBytes(kat['encapsulationRandomnessHex'] as String),
    );
    expect(ciphertext.length, XWing.ciphertextBytes);
    expect(toHex(ciphertext.sublist(0, 16)), kat['ciphertextPrefixHex']);
    expect(toHex(sha256.convert(ciphertext).bytes), kat['ciphertextSha256Hex']);
    expect(toHex(sharedSecret), kat['sharedSecretHex']);
    expect(toHex(xwing.decapsulate(ciphertext, seed)), kat['sharedSecretHex']);
  });

  test(
    'random encapsulation round-trips and tampering yields another secret',
    () {
      final seed = xwing.generateSeed();
      final publicKey = xwing.publicKeyFromSeed(seed);
      final (sharedSecret, ciphertext) = xwing.encapsulate(publicKey);
      expect(xwing.decapsulate(ciphertext, seed), sharedSecret);

      for (final index in [0, 1087, 1088, 1119]) {
        final tampered = Uint8List.fromList(ciphertext)..[index] ^= 1;
        expect(xwing.decapsulate(tampered, seed), isNot(sharedSecret));
      }
    },
  );

  test('rejects wrong lengths before any KEM work', () {
    final seed = Uint8List(32);
    expect(() => xwing.decapsulate(Uint8List(1119), seed), throwsArgumentError);
    expect(
      () => xwing.encapsulateDerandomized(Uint8List(1215), Uint8List(64)),
      throwsArgumentError,
    );
    expect(() => xwing.publicKeyFromSeed(Uint8List(31)), throwsArgumentError);
  });

  test(
    'rejects an encapsulation key that fails the FIPS 203 modulus check',
    () {
      final publicKey = xwing.publicKeyFromSeed(Uint8List(32));
      publicKey[0] = 0xff;
      publicKey[1] |= 0x0f;
      expect(
        () => xwing.encapsulateDerandomized(publicKey, Uint8List(64)),
        throwsArgumentError,
      );
    },
  );
}
