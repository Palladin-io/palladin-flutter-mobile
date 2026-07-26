import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../../core/crypto/sodium_provider.dart';
import 'vault_protocol_aad.dart';
import 'vault_protocol_bytes.dart';

/// Expected authenticated context for decrypting a Vault envelope.
final class VaultEnvelopeExpectations {
  const VaultEnvelopeExpectations({
    required this.aadContext,
    required this.minimumMemberKeyGeneration,
  });

  final Map<String, Object?> aadContext;
  final int minimumMemberKeyGeneration;
}

/// Dedicated Vault protocol 2 AEAD and sealed-package service.
abstract interface class VaultEnvelopeCryptography {
  Future<Uint8List> decrypt({
    required VaultAadProfile profile,
    required Map<String, Object?> envelope,
    required Uint8List key,
    required VaultEnvelopeExpectations expected,
  });

  Future<Map<String, String>> encrypt({
    required VaultAadProfile profile,
    required Map<String, Object?> context,
    required Uint8List plaintext,
    required Uint8List key,
  });
}

/// Sodium implementation of [VaultEnvelopeCryptography].
final class VaultProtocolEnvelopeService implements VaultEnvelopeCryptography {
  VaultProtocolEnvelopeService({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  static const int _maximumSealedPlaintextBytes = 4096;
  static const Map<VaultAadProfile, int> _maximumCiphertextBytes = {
    VaultAadProfile.memberVaultMetadata: 16384,
    VaultAadProfile.memberIndex: 32768,
    VaultAadProfile.memberSecret: 262144,
    VaultAadProfile.agentDiscovery: 16384,
    VaultAadProfile.entryKeyWrapper: 48,
    VaultAadProfile.vaultPrivateKey: 4096,
    VaultAadProfile.vaultDiscoveryKey: 256,
    VaultAadProfile.encryptedReason: 4096,
    VaultAadProfile.grantPayload: 262144,
  };

  @override
  Future<Uint8List> decrypt({
    required VaultAadProfile profile,
    required Map<String, Object?> envelope,
    required Uint8List key,
    required VaultEnvelopeExpectations expected,
  }) async {
    if (key.length != 32) {
      throw const FormatException('Vault envelope key must be 32 bytes');
    }
    assertVaultEnvelopeBindings(profile, envelope);
    assertVaultEnvelopeBindings(profile, expected.aadContext);
    final aad = encodeVaultAad(profile, envelope);
    final expectedAad = encodeVaultAad(profile, expected.aadContext);
    if (!VaultProtocolBytes.constantTimeEquals(aad, expectedAad)) {
      throw const FormatException(
        'Vault envelope authenticated context mismatch',
      );
    }
    final header = (envelope['header'] as Map).cast<String, Object?>();
    final generation = header['memberKeyGeneration'];
    if (generation is! int ||
        generation < expected.minimumMemberKeyGeneration) {
      throw const FormatException('stale key generation');
    }
    final nonceValue = header['nonce'];
    if (nonceValue is! String) throw const FormatException('missing nonce');
    final nonce = VaultProtocolBytes.base64UrlDecode(nonceValue);
    if (nonce.length != 24) {
      throw const FormatException('Vault envelope nonce must be 24 bytes');
    }
    final encodedCiphertext =
        envelope['ciphertext'] ?? envelope['wrappedEntryDekByVk'];
    if (encodedCiphertext is! String) {
      throw const FormatException('missing Vault ciphertext');
    }
    final ciphertext = VaultProtocolBytes.base64UrlDecode(
      encodedCiphertext,
      maximumBytes: _maximumCiphertextBytes[profile],
    );
    final sodium = await _sodiumLoader();
    final secureKey = SecureKey.fromList(sodium, key);
    try {
      return sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: ciphertext,
        nonce: nonce,
        key: secureKey,
        additionalData: aad,
      );
    } on SodiumException {
      throw const FormatException('Vault envelope authentication failed');
    } finally {
      secureKey.dispose();
      nonce.fillRange(0, nonce.length, 0);
      ciphertext.fillRange(0, ciphertext.length, 0);
      aad.fillRange(0, aad.length, 0);
      expectedAad.fillRange(0, expectedAad.length, 0);
    }
  }

  @override
  Future<Map<String, String>> encrypt({
    required VaultAadProfile profile,
    required Map<String, Object?> context,
    required Uint8List plaintext,
    required Uint8List key,
  }) async {
    if (key.length != 32) {
      throw const FormatException('Vault envelope key must be 32 bytes');
    }
    if (plaintext.length + 16 > _maximumCiphertextBytes[profile]!) {
      throw const FormatException('Vault plaintext exceeds envelope limit');
    }
    assertVaultEnvelopeBindings(profile, context);
    final aad = encodeVaultAad(profile, context);
    final sodium = await _sodiumLoader();
    final secureKey = SecureKey.fromList(sodium, key);
    final message = Uint8List.fromList(plaintext);
    final nonce = sodium.randombytes.buf(
      sodium.crypto.aeadXChaCha20Poly1305IETF.nonceBytes,
    );
    try {
      final ciphertext = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: message,
        nonce: nonce,
        key: secureKey,
        additionalData: aad,
      );
      return {
        'nonce': VaultProtocolBytes.base64UrlEncode(nonce),
        'ciphertext': VaultProtocolBytes.base64UrlEncode(ciphertext),
      };
    } finally {
      secureKey.dispose();
      message.fillRange(0, message.length, 0);
      nonce.fillRange(0, nonce.length, 0);
      aad.fillRange(0, aad.length, 0);
    }
  }

  Future<Uint8List> sealPackage({
    required Uint8List packageBytes,
    required Uint8List recipientPublicKey,
  }) async {
    if (packageBytes.isEmpty ||
        packageBytes.length > _maximumSealedPlaintextBytes ||
        recipientPublicKey.length != 32) {
      throw const FormatException('invalid Vault package or recipient key');
    }
    final sodium = await _sodiumLoader();
    final plaintext = Uint8List.fromList(packageBytes);
    try {
      return sodium.crypto.box.seal(
        message: plaintext,
        publicKey: recipientPublicKey,
      );
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Future<Uint8List> openPackage({
    required Uint8List ciphertext,
    required Uint8List recipientPublicKey,
    required Uint8List recipientPrivateKey,
  }) async {
    if (recipientPublicKey.length != 32 || recipientPrivateKey.length != 32) {
      throw const FormatException('invalid recipient key length');
    }
    final sodium = await _sodiumLoader();
    final overhead = sodium.crypto.box.sealBytes;
    if (ciphertext.length <= overhead ||
        ciphertext.length > _maximumSealedPlaintextBytes + overhead) {
      throw const FormatException('sealed Vault package exceeds limits');
    }
    final privateKey = SecureKey.fromList(sodium, recipientPrivateKey);
    try {
      return sodium.crypto.box.sealOpen(
        cipherText: ciphertext,
        publicKey: recipientPublicKey,
        secretKey: privateKey,
      );
    } on SodiumException {
      throw const FormatException('sealed Vault package authentication failed');
    } finally {
      privateKey.dispose();
    }
  }
}
