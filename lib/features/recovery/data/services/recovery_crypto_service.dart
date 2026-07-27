import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../../onboarding/domain/crypto_params.dart';
import '../../../onboarding/domain/mnemonic.dart' as mnemonic;
import '../../../unlock/data/services/identity_kdf_service.dart';
import '../../domain/recovery_exceptions.dart';
import '../models/recover_account_request.dart';

/// Bundle returned from [RecoveryCryptoService.recoverAccount].
///
/// [request] is the ready-to-ship payload for `PUT /api/account/recovery`.
/// [newRecoveryMnemonic] is the freshly generated 24-word mnemonic so
/// the UI can display it to the user for safekeeping.
class RecoveryResult {
  const RecoveryResult({
    required this.request,
    required this.newRecoveryMnemonic,
  });

  final RecoverAccountRequest request;
  final List<String> newRecoveryMnemonic;
}

/// Zero-knowledge crypto pipeline for the account-recovery flow.
///
/// Mirrors the web panel's `useRecover` mutation:
/// 1. Derive the recovery key (RK) from `mnemonic + recoverySalt` via
///    Argon2id, then open `encryptedPrivateKeyByRecovery` with it. A MAC
///    failure surfaces as [WrongRecoveryKeyException].
/// 2. Derive a fresh master key (MK) from `newPassword + newSalt` and
///    re-wrap the private key with it.
/// 3. Generate a fresh 24-word mnemonic and a fresh recovery salt,
///    derive the new RK, and re-wrap the private key with it.
/// 4. Return a [RecoveryResult] containing the recovery request payload
///    and the new mnemonic for the UI to display.
///
/// All derived keys and the raw private key are zeroed before returning
/// so no secret material lingers past this method's stack frame.
class RecoveryCryptoService {
  RecoveryCryptoService({
    IdentityKdfService? identityKdfService,
    Future<SodiumSumo> Function()? sodiumLoader,
  }) : _identityKdfService = identityKdfService ?? IdentityKdfService(),
       _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final IdentityKdfService _identityKdfService;
  final Future<SodiumSumo> Function() _sodiumLoader;

  /// Validates that [recoveryMnemonic] can unwrap the supplied
  /// `encryptedPrivateKeyByRecovery`. Used by the first wizard step
  /// to give the user immediate feedback before asking for a new
  /// master password.
  ///
  /// Runs Argon2id + one `crypto_secretbox_open_easy` — ~300 ms on a
  /// typical phone. Cheaper than re-running the full [recoverAccount]
  /// pipeline (which also derives MK, generates a new mnemonic, and
  /// re-wraps the private key twice).
  ///
  /// Throws [WrongRecoveryKeyException] if decryption fails.
  Future<void> validateRecoveryMnemonic({
    required String recoveryMnemonic,
    required String recoverySaltBase64,
    required String encryptedPrivateKeyByRecoveryBase64,
  }) async {
    final sodium = await _sodiumLoader();
    final salt = base64.decode(recoverySaltBase64);
    final recoveryKey = _deriveKey(sodium, recoveryMnemonic, salt);
    try {
      final privateKey = _openPrivateKey(
        sodium,
        recoveryKey,
        encryptedPrivateKeyByRecoveryBase64,
      );
      // Zeroize immediately — the caller never gets to see it, validation
      // only cares that the MAC check passed.
      privateKey.fillRange(0, privateKey.length, 0);
    } finally {
      recoveryKey.dispose();
    }
  }

  /// Runs the end-to-end recovery pipeline.
  ///
  /// Throws:
  ///   * [WrongRecoveryKeyException] — the supplied mnemonic does not
  ///     decrypt `encryptedPrivateKeyByRecoveryBase64`.
  Future<RecoveryResult> recoverAccount({
    required String recoveryMnemonic,
    required String newPassword,
    required String recoverySaltBase64,
    required String encryptedPrivateKeyByRecoveryBase64,
    required String accountId,
    required int baseCredentialRevision,
    required int basePrivateKeyWrapRevision,
  }) async {
    final sodium = await _sodiumLoader();
    final recoverySalt = base64.decode(recoverySaltBase64);

    final recoveryKey = _deriveKey(sodium, recoveryMnemonic, recoverySalt);
    Uint8List? privateKey;
    IdentityKdfOutputs? outputs;
    try {
      // Step 1: unwrap the private key with the user-supplied mnemonic.
      privateKey = _openPrivateKey(
        sodium,
        recoveryKey,
        encryptedPrivateKeyByRecoveryBase64,
      );

      // Step 2: re-wrap under a fresh MK derived from the new password.
      final newSalt = sodium.randombytes.buf(IdentityKdfProfile.saltBytes);
      outputs = await _identityKdfService.derive(
        password: newPassword,
        accountId: accountId,
        kdfSalt: newSalt,
      );
      final newMasterKey = SecureKey.fromList(sodium, outputs.masterKey);
      late final Uint8List newEncryptedPrivateKey;
      try {
        newEncryptedPrivateKey = _encryptWithKey(
          sodium,
          plaintext: privateKey,
          key: newMasterKey,
        );
      } finally {
        newMasterKey.dispose();
      }

      // Step 3: generate a new mnemonic and re-wrap under a fresh RK.
      final newMnemonic = mnemonic.generateRecoveryMnemonic();
      final newRecoverySalt = sodium.randombytes.buf(CryptoParams.saltLength);
      final newRecoveryKey = _deriveKey(
        sodium,
        mnemonic.joinMnemonic(newMnemonic),
        newRecoverySalt,
      );
      late final Uint8List newEncryptedPrivateKeyByRecovery;
      try {
        newEncryptedPrivateKeyByRecovery = _encryptWithKey(
          sodium,
          plaintext: privateKey,
          key: newRecoveryKey,
        );
      } finally {
        newRecoveryKey.dispose();
      }

      final newAuthCredential = baseCredentialRevision > 0
          ? Uint8List.fromList(outputs.authCredential)
          : null;
      return RecoveryResult(
        request: RecoverAccountRequest(
          baseCredentialRevision: baseCredentialRevision,
          basePrivateKeyWrapRevision: basePrivateKeyWrapRevision,
          newKdfSalt: newSalt,
          newAuthCredential: newAuthCredential,
          newEncryptedPrivateKey: newEncryptedPrivateKey,
          newRecoverySalt: newRecoverySalt,
          newEncryptedPrivateKeyByRecovery: newEncryptedPrivateKeyByRecovery,
        ),
        newRecoveryMnemonic: newMnemonic,
      );
    } finally {
      // Zeroize the plaintext private key bytes in memory — the wrapped
      // copies in the payload are the only thing that should survive.
      if (privateKey != null) {
        privateKey.fillRange(0, privateKey.length, 0);
      }
      outputs?.dispose();
      recoveryKey.dispose();
    }
  }

  /// Splits the base64-decoded blob into `nonce || ciphertext` and runs
  /// `crypto_secretbox_open_easy` against [key].
  ///
  /// Throws [WrongRecoveryKeyException] on any failure — libsodium's
  /// MAC check is constant-time, so callers cannot (and should not)
  /// distinguish between "wrong mnemonic" and "tampered ciphertext".
  Uint8List _openPrivateKey(
    SodiumSumo sodium,
    SecureKey key,
    String encryptedBase64,
  ) {
    final combined = base64.decode(encryptedBase64);
    final nonceBytes = sodium.crypto.secretBox.nonceBytes;

    if (combined.length <= nonceBytes) {
      throw const WrongRecoveryKeyException();
    }

    final nonce = Uint8List.sublistView(combined, 0, nonceBytes);
    final cipher = Uint8List.sublistView(combined, nonceBytes);

    try {
      return sodium.crypto.secretBox.openEasy(
        cipherText: cipher,
        nonce: nonce,
        key: key,
      );
    } on SodiumException {
      throw const WrongRecoveryKeyException();
    }
  }

  /// Runs `crypto_pwhash` (Argon2id) with the project-wide cost parameters
  /// and returns a [SecureKey] backed by locked memory.
  SecureKey _deriveKey(SodiumSumo sodium, String password, Uint8List salt) {
    final utf8Bytes = utf8.encode(password);
    return sodium.crypto.pwhash.call(
      outLen: CryptoParams.derivedKeyLength,
      password: Int8List.fromList(utf8Bytes),
      salt: salt,
      opsLimit: CryptoParams.argon2OpsLimit,
      memLimit: CryptoParams.argon2MemLimit,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
  }

  /// Encrypts [plaintext] with `crypto_secretbox_easy` and returns a
  /// single byte blob of the form `nonce || ciphertext`, matching the
  /// format used by the web panel and onboarding.
  Uint8List _encryptWithKey(
    SodiumSumo sodium, {
    required Uint8List plaintext,
    required SecureKey key,
  }) {
    final nonce = sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
    final cipher = sodium.crypto.secretBox.easy(
      message: plaintext,
      nonce: nonce,
      key: key,
    );

    final combined = Uint8List(nonce.length + cipher.length);
    combined.setRange(0, nonce.length, nonce);
    combined.setRange(nonce.length, combined.length, cipher);
    return combined;
  }
}
