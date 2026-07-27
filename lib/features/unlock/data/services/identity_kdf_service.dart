import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';

/// Frozen password-only Identity KDF v1 profile.
abstract final class IdentityKdfProfile {
  static const securityVersion = 1;
  static const id = 'identity-argon2id-password-v1';
  static const memoryKiB = 32768;
  static const iterations = 2;
  static const parallelism = 1;
  static const outputBytes = 32;
  static const saltBytes = 16;
  static const authCredentialInfo =
      'palladin/identity/password-v1/auth-credential';
  static const masterKeyInfo = 'palladin/identity/password-v1/master-key';
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

/// Domain-separated outputs of the v1 Identity derivation.
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

  /// Generates a fresh per-account v1 Argon2id salt.
  Future<Uint8List> generateKdfSalt() async {
    final sodium = await _sodiumLoader();
    return sodium.randombytes.buf(IdentityKdfProfile.saltBytes);
  }

  /// Derives v1 outputs from the exact UTF-8 password bytes.
  Future<IdentityKdfOutputs> derive({
    required String password,
    required String accountId,
    required Uint8List kdfSalt,
  }) async {
    if (kdfSalt.length != IdentityKdfProfile.saltBytes) {
      throw const FormatException('Invalid Identity KDF input length');
    }
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    SecureKey? root;
    try {
      final sodium = await _sodiumLoader();
      root = sodium.crypto.pwhash.call(
        outLen: IdentityKdfProfile.outputBytes,
        password: Int8List.sublistView(passwordBytes),
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
        );
      } finally {
        rootBytes.fillRange(0, rootBytes.length, 0);
      }
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      root?.dispose();
    }
  }

  /// Exposes the non-Argon portion for language-neutral contract vectors.
  IdentityKdfOutputs deriveOutputsFromRoot({
    required Uint8List accountRoot,
    required String accountId,
  }) {
    if (accountRoot.length != IdentityKdfProfile.outputBytes) {
      throw const FormatException('Invalid Identity KDF input length');
    }
    final outputSalt = _uuidBytes(accountId);
    try {
      return IdentityKdfOutputs(
        authCredential: _hkdf(
          accountRoot,
          outputSalt,
          IdentityKdfProfile.authCredentialInfo,
        ),
        masterKey: _hkdf(
          accountRoot,
          outputSalt,
          IdentityKdfProfile.masterKeyInfo,
        ),
      );
    } finally {
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

  Uint8List _concat(List<Uint8List> parts) {
    final builder = BytesBuilder(copy: false);
    for (final part in parts) {
      builder.add(part);
    }
    return builder.takeBytes();
  }
}
