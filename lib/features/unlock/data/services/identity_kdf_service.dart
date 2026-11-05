import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/storage/account_secret_store.dart';

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

/// Identity security version 2 profile: password plus Secret Key
/// (`identity-kdf/v2` Account Secret, unchanged by the v3 addendum).
abstract final class IdentityKdfProfileV2 {
  static const securityVersion = 2;
  static const id = 'identity-argon2id-account-secret-v2';
  static const memoryKiB = 32768;
  static const iterations = 2;
  static const parallelism = 1;
  static const outputBytes = 32;
  static const saltBytes = 16;
  static const accountSecretBytes = 32;
  static const maximumPasswordUtf8Bytes = 1024;
  static const authCredentialInfo = 'palladin:identity:v2:auth-credential';
  static const masterKeyInfo = 'palladin:identity:v2:master-key';
}

/// Registered profiles this release can derive.
enum IdentityKdfVersion { passwordV1, accountSecretV2 }

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

/// The account is at security version 2 but this device holds no Secret Key.
final class AccountSecretRequiredException implements Exception {
  const AccountSecretRequiredException();
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
  IdentityKdfService({
    Future<SodiumSumo> Function()? sodiumLoader,
    this._accountSecrets,
  }) : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;
  final AccountSecretStore? _accountSecrets;

  /// Runs [action] with this device's Secret Key for [accountId] and wipes
  /// the copy afterwards.
  Future<T> withStoredAccountSecret<T>(
    String accountId,
    Future<T> Function(Uint8List accountSecret) action,
  ) async {
    final secret = await (_accountSecrets ?? AccountSecretStore()).read(
      accountId,
    );
    if (secret == null) throw const AccountSecretRequiredException();
    try {
      return await action(secret);
    } finally {
      secret.fillRange(0, secret.length, 0);
    }
  }

  /// Version-2 derivation with the Secret Key stored on this device.
  Future<IdentityKdfOutputs> deriveWithStoredSecret({
    required String password,
    required String accountId,
    required Uint8List kdfSalt,
  }) => withStoredAccountSecret(
    accountId,
    (secret) => deriveV2(
      password: password,
      accountId: accountId,
      kdfSalt: kdfSalt,
      accountSecret: secret,
    ),
  );

  /// Validates all server-selected metadata before allocating KDF memory and
  /// returns the profile to derive. A version-1 profile is accepted only while
  /// the account minimum still allows it (unlock-and-migrate).
  IdentityKdfVersion assertSupported(IdentityKdfMetadata metadata) {
    if (metadata.minimumSecurityVersion >
        IdentityKdfProfileV2.securityVersion) {
      throw const UnsupportedIdentityKdfException('upgrade-required');
    }
    if (metadata.securityVersion < metadata.minimumSecurityVersion) {
      throw const UnsupportedIdentityKdfException('security-version-downgrade');
    }
    final version = switch ((metadata.securityVersion, metadata.profileId)) {
      (IdentityKdfProfile.securityVersion, IdentityKdfProfile.id) =>
        IdentityKdfVersion.passwordV1,
      (IdentityKdfProfileV2.securityVersion, IdentityKdfProfileV2.id) =>
        IdentityKdfVersion.accountSecretV2,
      _ => throw const UnsupportedIdentityKdfException(
        'unsupported-kdf-profile',
      ),
    };
    _decodeBase64Url(
      metadata.kdfSalt,
      IdentityKdfProfile.saltBytes,
    ).fillRange(0, IdentityKdfProfile.saltBytes, 0);
    return version;
  }

  /// Generates a fresh per-account v1 Argon2id salt.
  Future<Uint8List> generateKdfSalt() async {
    final sodium = await _sodiumLoader();
    return sodium.randombytes.buf(IdentityKdfProfile.saltBytes);
  }

  /// Derives password-only v1 outputs; used only to unlock and migrate a
  /// security-version-1 account.
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
      root = sodium.crypto.pwhash.callRaw(
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

  /// Derives security-version-2 outputs from the password and Secret Key.
  Future<IdentityKdfOutputs> deriveV2({
    required String password,
    required String accountId,
    required Uint8List kdfSalt,
    required Uint8List accountSecret,
  }) async {
    if (kdfSalt.length != IdentityKdfProfileV2.saltBytes ||
        accountSecret.length != IdentityKdfProfileV2.accountSecretBytes) {
      throw const FormatException('Invalid Identity KDF input length');
    }
    final prehash = passwordPrehashV2(
      password: password,
      accountSecret: accountSecret,
    );
    SecureKey? root;
    try {
      final sodium = await _sodiumLoader();
      root = sodium.crypto.pwhash.callRaw(
        outLen: IdentityKdfProfileV2.outputBytes,
        password: Int8List.sublistView(prehash),
        salt: kdfSalt,
        opsLimit: IdentityKdfProfileV2.iterations,
        memLimit: IdentityKdfProfileV2.memoryKiB * 1024,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
      final rootBytes = root.extractBytes();
      try {
        return deriveV2OutputsFromRoot(
          accountRoot: rootBytes,
          accountId: accountId,
          kdfSalt: kdfSalt,
        );
      } finally {
        rootBytes.fillRange(0, rootBytes.length, 0);
      }
    } finally {
      prehash.fillRange(0, prehash.length, 0);
      root?.dispose();
    }
  }

  /// `HMAC-SHA-256(AccountSecret, PLDNID2PW || u16(2) || u32(len) || pw)`.
  Uint8List passwordPrehashV2({
    required String password,
    required Uint8List accountSecret,
  }) {
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    if (passwordBytes.length > IdentityKdfProfileV2.maximumPasswordUtf8Bytes) {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      throw const FormatException('Password exceeds the Identity KDF limit');
    }
    final length = ByteData(4)..setUint32(0, passwordBytes.length);
    final input = _concat([
      Uint8List.fromList(ascii.encode('PLDNID2PW')),
      Uint8List.fromList([0, IdentityKdfProfileV2.securityVersion]),
      length.buffer.asUint8List(),
      passwordBytes,
    ]);
    try {
      return Uint8List.fromList(
        Hmac(sha256, accountSecret).convert(input).bytes,
      );
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      input.fillRange(0, input.length, 0);
    }
  }

  /// Non-Argon portion of the v2 derivation for contract vectors.
  IdentityKdfOutputs deriveV2OutputsFromRoot({
    required Uint8List accountRoot,
    required String accountId,
    required Uint8List kdfSalt,
  }) {
    if (accountRoot.length != IdentityKdfProfileV2.outputBytes) {
      throw const FormatException('Invalid Identity KDF input length');
    }
    final outputSalt = outputSaltV2(accountId: accountId, kdfSalt: kdfSalt);
    try {
      return IdentityKdfOutputs(
        authCredential: _hkdf(
          accountRoot,
          outputSalt,
          IdentityKdfProfileV2.authCredentialInfo,
        ),
        masterKey: _hkdf(
          accountRoot,
          outputSalt,
          IdentityKdfProfileV2.masterKeyInfo,
        ),
      );
    } finally {
      outputSalt.fillRange(0, outputSalt.length, 0);
    }
  }

  /// `SHA-256(PLDNID2HK || u16(2) || accountId || kdfSalt)`.
  Uint8List outputSaltV2({
    required String accountId,
    required Uint8List kdfSalt,
  }) => Uint8List.fromList(
    sha256
        .convert(
          _concat([
            Uint8List.fromList(ascii.encode('PLDNID2HK')),
            Uint8List.fromList([0, IdentityKdfProfileV2.securityVersion]),
            _uuidBytes(accountId),
            kdfSalt,
          ]),
        )
        .bytes,
  );

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
