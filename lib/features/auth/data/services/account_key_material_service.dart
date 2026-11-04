import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../../../../core/crypto/key_wrapper/key_wrapper.dart';
import '../../../../core/crypto/sodium_provider.dart';
import '../../../onboarding/domain/crypto_params.dart';
import '../../../unlock/data/services/identity_kdf_service.dart';

/// Security-version-2 key material for setup, migration and recovery.
///
/// Only the wire fields leave the device. The caller owns [accountSecret],
/// [masterKey], [memberPrivateKey] and [authCredential] and must call
/// [dispose] once they are handed off or abandoned.
final class AccountKeyMaterialV2 {
  AccountKeyMaterialV2._({
    required this.accountSecret,
    required this.kdfSalt,
    required this.authCredential,
    required this.masterKey,
    required this.memberPrivateKey,
    required this.memberPublicKey,
    required this.encryptedPrivateKey,
    required this.recoverySalt,
    required this.encryptedPrivateKeyByRecovery,
  });

  final Uint8List accountSecret;
  final Uint8List kdfSalt;
  final Uint8List authCredential;
  final Uint8List masterKey;
  final Uint8List memberPrivateKey;
  final Uint8List memberPublicKey;
  final Uint8List encryptedPrivateKey;
  final Uint8List recoverySalt;
  final Uint8List encryptedPrivateKeyByRecovery;

  WrapperSuite get memberKeySuite => WrapperSuite.memberKeySuite;

  void dispose() {
    for (final secret in [
      accountSecret,
      authCredential,
      masterKey,
      memberPrivateKey,
    ]) {
      secret.fillRange(0, secret.length, 0);
    }
  }
}

/// Builds version-2 credentials, wraps and recovery material client-side.
class AccountKeyMaterialService {
  AccountKeyMaterialService({
    required this._identityKdfService,
    Future<SodiumSumo> Function()? sodiumLoader,
  }) : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final IdentityKdfService _identityKdfService;
  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Generates a fresh Secret Key, KDF salt and recovery salt. Without
  /// [existingMemberPrivateKey] a new member key is generated; recovery passes
  /// the unchanged key.
  Future<AccountKeyMaterialV2> build({
    required String password,
    required String accountId,
    required List<String> recoveryMnemonic,
    Uint8List? existingMemberPrivateKey,
  }) async {
    final sodium = await _sodiumLoader();
    final accountSecret = sodium.randombytes.buf(
      IdentityKdfProfileV2.accountSecretBytes,
    );
    final kdfSalt = sodium.randombytes.buf(IdentityKdfProfileV2.saltBytes);
    final recoverySalt = sodium.randombytes.buf(CryptoParams.saltLength);
    final memberPrivateKey = existingMemberPrivateKey == null
        ? sodium.randombytes.buf(32)
        : Uint8List.fromList(existingMemberPrivateKey);
    IdentityKdfOutputs? outputs;
    SecureKey? recoveryKey;
    try {
      outputs = await _identityKdfService.deriveV2(
        password: password,
        accountId: accountId,
        kdfSalt: kdfSalt,
        accountSecret: accountSecret,
      );
      recoveryKey = sodium.crypto.pwhash.callRaw(
        outLen: CryptoParams.derivedKeyLength,
        password: Int8List.fromList(utf8.encode(recoveryMnemonic.join(' '))),
        salt: recoverySalt,
        opsLimit: CryptoParams.argon2OpsLimit,
        memLimit: CryptoParams.argon2MemLimit,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
      final masterKey = SecureKey.fromList(sodium, outputs.masterKey);
      try {
        return AccountKeyMaterialV2._(
          accountSecret: accountSecret,
          kdfSalt: kdfSalt,
          authCredential: Uint8List.fromList(outputs.authCredential),
          masterKey: Uint8List.fromList(outputs.masterKey),
          memberPrivateKey: memberPrivateKey,
          memberPublicKey: memberPublicKeyFromPrivate(sodium, memberPrivateKey),
          encryptedPrivateKey: _secretBox(sodium, memberPrivateKey, masterKey),
          recoverySalt: recoverySalt,
          encryptedPrivateKeyByRecovery: _secretBox(
            sodium,
            memberPrivateKey,
            recoveryKey,
          ),
        );
      } finally {
        masterKey.dispose();
      }
    } catch (_) {
      accountSecret.fillRange(0, accountSecret.length, 0);
      memberPrivateKey.fillRange(0, memberPrivateKey.length, 0);
      rethrow;
    } finally {
      outputs?.dispose();
      recoveryKey?.dispose();
    }
  }

  /// Wraps [plaintext] under [masterKey] in the shared `nonce || box` form.
  Future<Uint8List> wrapUnderMasterKey(
    Uint8List masterKey,
    Uint8List plaintext,
  ) async {
    final sodium = await _sodiumLoader();
    final key = SecureKey.fromList(sodium, masterKey);
    try {
      return _secretBox(sodium, plaintext, key);
    } finally {
      key.dispose();
    }
  }

  /// Opens a `nonce || box` value wrapped under [masterKey]; null on failure.
  Future<Uint8List?> openUnderMasterKey(
    Uint8List masterKey,
    Uint8List wrapped,
  ) async {
    final sodium = await _sodiumLoader();
    final nonceBytes = sodium.crypto.secretBox.nonceBytes;
    if (wrapped.length <= nonceBytes) return null;
    final key = SecureKey.fromList(sodium, masterKey);
    try {
      return sodium.crypto.secretBox.openEasy(
        cipherText: Uint8List.sublistView(wrapped, nonceBytes),
        nonce: Uint8List.sublistView(wrapped, 0, nonceBytes),
        key: key,
      );
    } on SodiumException {
      return null;
    } finally {
      key.dispose();
    }
  }

  static Uint8List _secretBox(
    SodiumSumo sodium,
    Uint8List plaintext,
    SecureKey key,
  ) {
    final nonce = sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
    final cipher = sodium.crypto.secretBox.easy(
      message: plaintext,
      nonce: nonce,
      key: key,
    );
    return Uint8List.fromList([...nonce, ...cipher]);
  }
}
