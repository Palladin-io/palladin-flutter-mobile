import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';

/// Frozen Identity KDF v2 profile from the shared protocol registry.
abstract final class IdentityKdfProfile {
  static const securityVersion = 2;
  static const id = 'identity-argon2id-account-secret-v2';
  static const legacyId = 'identity-argon2id-legacy-v1';
  static const memoryKiB = 32768;
  static const iterations = 2;
  static const parallelism = 1;
  static const outputBytes = 32;
  static const accountSecretBytes = 32;
  static const saltBytes = 16;
  static const maximumPasswordUtf8Bytes = 1024;
}

/// Public metadata authenticated by the backend Identity state machine.
final class IdentityKdfMetadata {
  const IdentityKdfMetadata({
    required this.securityVersion,
    required this.minimumSecurityVersion,
    required this.profileId,
    required this.kdfSalt,
    required this.credentialRevision,
    required this.privateKeyWrapRevision,
    this.deviceWrapperMetadata,
  });

  final int securityVersion;
  final int minimumSecurityVersion;
  final String profileId;
  final String kdfSalt;
  final int credentialRevision;
  final int privateKeyWrapRevision;
  final String? deviceWrapperMetadata;

  factory IdentityKdfMetadata.fromJson(Map<String, dynamic> json) =>
      IdentityKdfMetadata(
        securityVersion: json['securityVersion'] as int,
        minimumSecurityVersion: json['minimumSecurityVersion'] as int,
        profileId: json['profileId'] as String,
        kdfSalt: json['kdfSalt'] as String,
        credentialRevision: json['credentialRevision'] as int,
        privateKeyWrapRevision: json['privateKeyWrapRevision'] as int,
        deviceWrapperMetadata: json['deviceWrapperMetadata'] as String?,
      );
}

/// Thrown before Argon2 allocation for unsupported or downgraded metadata.
final class UnsupportedIdentityKdfException implements Exception {
  const UnsupportedIdentityKdfException(this.code);
  final String code;
}

/// Domain-separated outputs of the v2 Identity derivation.
final class IdentityKdfOutputs {
  const IdentityKdfOutputs({
    required this.authCredential,
    required this.masterKey,
  });

  final Uint8List authCredential;
  final Uint8List masterKey;

  void dispose() {
    authCredential.fillRange(0, authCredential.length, 0);
    masterKey.fillRange(0, masterKey.length, 0);
  }
}

/// Implements the byte-exact, versioned Identity KDF contract.
class IdentityKdfService {
  IdentityKdfService({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Validates all server-selected metadata before allocating KDF memory.
  void assertSupported(IdentityKdfMetadata metadata) {
    if (metadata.minimumSecurityVersion > IdentityKdfProfile.securityVersion) {
      throw const UnsupportedIdentityKdfException('upgrade-required');
    }
    if (metadata.securityVersion != IdentityKdfProfile.securityVersion ||
        metadata.profileId != IdentityKdfProfile.id) {
      throw const UnsupportedIdentityKdfException('unsupported-kdf-profile');
    }
    _decodeBase64Url(
      metadata.kdfSalt,
      IdentityKdfProfile.saltBytes,
    ).fillRange(0, IdentityKdfProfile.saltBytes, 0);
  }

  /// Generates the mandatory account-wide client secret.
  Future<Uint8List> generateAccountSecret() async {
    final sodium = await _sodiumLoader();
    return sodium.randombytes.buf(IdentityKdfProfile.accountSecretBytes);
  }

  /// Generates a fresh v2 KDF salt.
  Future<Uint8List> generateKdfSalt() async {
    final sodium = await _sodiumLoader();
    return sodium.randombytes.buf(IdentityKdfProfile.saltBytes);
  }

  /// Derives v2 outputs. Inputs are borrowed; the caller retains ownership.
  Future<IdentityKdfOutputs> derive({
    required String password,
    required Uint8List accountSecret,
    required String accountId,
    required Uint8List kdfSalt,
  }) async {
    if (accountSecret.length != IdentityKdfProfile.accountSecretBytes ||
        kdfSalt.length != IdentityKdfProfile.saltBytes) {
      throw const FormatException('Invalid Identity KDF input length');
    }
    Uint8List? prehash;
    SecureKey? root;
    try {
      prehash = derivePasswordPrehash(password, accountSecret);
      final sodium = await _sodiumLoader();
      root = sodium.crypto.pwhash.call(
        outLen: IdentityKdfProfile.outputBytes,
        password: Int8List.fromList(prehash),
        salt: kdfSalt,
        opsLimit: IdentityKdfProfile.iterations,
        memLimit: IdentityKdfProfile.memoryKiB * 1024,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
      final rootBytes = root.extractBytes();
      try {
        return deriveOutputsFromRoot(
          accountRoot: rootBytes,
          accountId: accountId,
          kdfSalt: kdfSalt,
        );
      } finally {
        rootBytes.fillRange(0, rootBytes.length, 0);
      }
    } finally {
      prehash?.fillRange(0, prehash.length, 0);
      root?.dispose();
    }
  }

  /// Applies the exact length-framed HMAC prehash from the shared registry.
  /// The returned request-local buffer must be wiped by its caller.
  Uint8List derivePasswordPrehash(String password, Uint8List accountSecret) {
    if (accountSecret.length != IdentityKdfProfile.accountSecretBytes) {
      throw const FormatException('Invalid Identity KDF input length');
    }
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    if (passwordBytes.length > IdentityKdfProfile.maximumPasswordUtf8Bytes) {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      throw const FormatException('password-too-long');
    }
    final framed = _concat([
      Uint8List.fromList(ascii.encode('PLDNID2PW')),
      _u16(IdentityKdfProfile.securityVersion),
      _u32(passwordBytes.length),
      passwordBytes,
    ]);
    try {
      return Uint8List.fromList(
        Hmac(sha256, accountSecret).convert(framed).bytes,
      );
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      framed.fillRange(0, framed.length, 0);
    }
  }

  /// Exposes the non-Argon portion for language-neutral contract vectors.
  IdentityKdfOutputs deriveOutputsFromRoot({
    required Uint8List accountRoot,
    required String accountId,
    required Uint8List kdfSalt,
  }) {
    if (accountRoot.length != IdentityKdfProfile.outputBytes ||
        kdfSalt.length != IdentityKdfProfile.saltBytes) {
      throw const FormatException('Invalid Identity KDF input length');
    }
    final saltInput = _concat([
      Uint8List.fromList(ascii.encode('PLDNID2HK')),
      _u16(IdentityKdfProfile.securityVersion),
      _uuidBytes(accountId),
      kdfSalt,
    ]);
    final outputSalt = Uint8List.fromList(sha256.convert(saltInput).bytes);
    try {
      return IdentityKdfOutputs(
        authCredential: _hkdf(
          accountRoot,
          outputSalt,
          'palladin:identity:v2:auth-credential',
        ),
        masterKey: _hkdf(
          accountRoot,
          outputSalt,
          'palladin:identity:v2:master-key',
        ),
      );
    } finally {
      saltInput.fillRange(0, saltInput.length, 0);
      outputSalt.fillRange(0, outputSalt.length, 0);
    }
  }

  Uint8List _hkdf(Uint8List root, Uint8List salt, String infoValue) {
    final prk = Uint8List.fromList(Hmac(sha256, salt).convert(root).bytes);
    final info = Uint8List.fromList(ascii.encode(infoValue));
    final input = _concat([
      info,
      Uint8List.fromList([1]),
    ]);
    try {
      return Uint8List.fromList(Hmac(sha256, prk).convert(input).bytes);
    } finally {
      prk.fillRange(0, prk.length, 0);
      info.fillRange(0, info.length, 0);
      input.fillRange(0, input.length, 0);
    }
  }

  Uint8List _decodeBase64Url(String value, int expectedLength) {
    final normalized = base64Url.normalize(value);
    final decoded = Uint8List.fromList(base64Url.decode(normalized));
    if (decoded.length != expectedLength) {
      decoded.fillRange(0, decoded.length, 0);
      throw const FormatException('Invalid base64url field length');
    }
    return decoded;
  }

  Uint8List _uuidBytes(String value) {
    final hex = value.replaceAll('-', '');
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex)) {
      throw const FormatException(
        'Identity account ID must be an RFC 4122 UUID',
      );
    }
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  Uint8List _u16(int value) => Uint8List.fromList([value >> 8, value]);
  Uint8List _u32(int value) =>
      Uint8List.fromList([value >> 24, value >> 16, value >> 8, value]);

  Uint8List _concat(List<Uint8List> parts) {
    final builder = BytesBuilder(copy: false);
    for (final part in parts) {
      builder.add(part);
    }
    return builder.takeBytes();
  }
}
