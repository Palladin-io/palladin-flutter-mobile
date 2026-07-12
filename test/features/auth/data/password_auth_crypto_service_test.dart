import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/data/services/password_auth_crypto_service.dart';
import 'package:mobile_palladin/features/onboarding/domain/crypto_params.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

/// Byte-level verification of the Variant-A password-auth crypto:
///   * `authHash` and `MK` are two independent Argon2id derivations (two
///     salts) — the value sent to the server reveals nothing about MK.
///   * the registration bundle round-trips: MK opens `encryptedPrivateKey`,
///     the recovery key opens `encryptedPrivateKeyByRecovery`.
///   * a master-password change re-wraps the same private key under a
///     fresh MK and rejects a wrong current password.
///
/// libsodium must be loadable in the test host; in a pure-Dart `flutter
/// test` VM the platform channel is unavailable, so these self-skip with a
/// clear reason rather than failing CI. They run in full on a device host.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;
  var sodiumAvailable = false;

  setUpAll(() async {
    try {
      sodium = await SodiumSumoInit.init();
      sodiumAvailable = true;
    } catch (_) {
      sodiumAvailable = false;
    }
  });

  SecureKey deriveKey(String password, Uint8List salt) {
    return sodium.crypto.pwhash.call(
      outLen: CryptoParams.derivedKeyLength,
      password: Int8List.fromList(utf8.encode(password)),
      salt: salt,
      opsLimit: CryptoParams.argon2OpsLimit,
      memLimit: CryptoParams.argon2MemLimit,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
  }

  Uint8List open(String blobBase64, SecureKey key) {
    final combined = base64.decode(blobBase64);
    final nonceBytes = sodium.crypto.secretBox.nonceBytes;
    final nonce = Uint8List.sublistView(combined, 0, nonceBytes);
    final cipher = Uint8List.sublistView(combined, nonceBytes);
    return sodium.crypto.secretBox
        .openEasy(cipherText: cipher, nonce: nonce, key: key);
  }

  const password = 'CorrectHorseBatteryStaple!7';
  final mnemonic = List.generate(24, (i) => 'word$i');

  test('authHash and MK are independent derivations', () async {
    if (!sodiumAvailable) {
      markTestSkipped('libsodium not loadable in this test host');
      return;
    }
    final service = PasswordAuthCryptoService();
    final material = await service.buildRegistrationMaterial(
      password: password,
      recoveryMnemonic: mnemonic,
    );

    // authHash equals a direct Argon2id(password, authSalt).
    final expectedAuth = deriveKey(password, material.authSalt);
    expect(material.authHash, base64.encode(expectedAuth.extractBytes()));
    expectedAuth.dispose();

    // MK equals Argon2id(password, encSalt), and differs from authHash —
    // two salts, so the server's authHash cannot recover MK.
    final expectedMk = deriveKey(password, material.encSalt);
    expect(material.masterKey, expectedMk.extractBytes());
    expect(material.authHash, isNot(base64.encode(material.masterKey)));
    expect(material.authSalt, isNot(material.encSalt));
    expectedMk.dispose();
  });

  test('registration bundle round-trips under MK and recovery key',
      () async {
    if (!sodiumAvailable) {
      markTestSkipped('libsodium not loadable in this test host');
      return;
    }
    final service = PasswordAuthCryptoService();
    final material = await service.buildRegistrationMaterial(
      password: password,
      recoveryMnemonic: mnemonic,
    );

    final mk = deriveKey(password, material.encSalt);
    expect(
      open(base64.encode(material.encryptedPrivateKey), mk),
      material.privateKey,
    );
    mk.dispose();

    final rk = deriveKey(mnemonic.join(' '), material.recoverySalt);
    expect(
      open(base64.encode(material.encryptedPrivateKeyByRecovery), rk),
      material.privateKey,
    );
    rk.dispose();
  });

  test('deriveAuthHash matches the registration authHash for the same salt',
      () async {
    if (!sodiumAvailable) {
      markTestSkipped('libsodium not loadable in this test host');
      return;
    }
    final service = PasswordAuthCryptoService();
    final material = await service.buildRegistrationMaterial(
      password: password,
      recoveryMnemonic: mnemonic,
    );
    final authHash = await service.deriveAuthHash(
      password: password,
      authSaltBase64: base64.encode(material.authSalt),
    );
    expect(authHash, material.authHash);
  });

  test('change-password re-wraps the same private key under a fresh MK',
      () async {
    if (!sodiumAvailable) {
      markTestSkipped('libsodium not loadable in this test host');
      return;
    }
    final service = PasswordAuthCryptoService();
    final reg = await service.buildRegistrationMaterial(
      password: password,
      recoveryMnemonic: mnemonic,
    );

    const newPassword = 'An0ther-Str0ng-Passphrase!';
    final changed = await service.buildChangePasswordMaterial(
      currentPassword: password,
      newPassword: newPassword,
      currentAuthSaltBase64: base64.encode(reg.authSalt),
      currentEncSaltBase64: base64.encode(reg.encSalt),
      currentEncryptedPrivateKeyBase64: base64.encode(reg.encryptedPrivateKey),
    );

    // The private key is unchanged; only the wrapping key rotated.
    expect(changed.privateKey, reg.privateKey);
    expect(changed.encSalt, isNot(reg.encSalt));

    // currentAuthHash proves the old password against the old auth salt and
    // equals the registration authHash (same password + same salt).
    expect(changed.currentAuthHash, reg.authHash);

    final newMk = deriveKey(newPassword, changed.encSalt);
    expect(
      open(base64.encode(changed.encryptedPrivateKey), newMk),
      reg.privateKey,
    );
    expect(changed.masterKey, newMk.extractBytes());
    newMk.dispose();

    final newAuth = deriveKey(newPassword, changed.authSalt);
    expect(changed.authHash, base64.encode(newAuth.extractBytes()));
    newAuth.dispose();
  });

  test('change-password rejects a wrong current password', () async {
    if (!sodiumAvailable) {
      markTestSkipped('libsodium not loadable in this test host');
      return;
    }
    final service = PasswordAuthCryptoService();
    final reg = await service.buildRegistrationMaterial(
      password: password,
      recoveryMnemonic: mnemonic,
    );

    expect(
      () => service.buildChangePasswordMaterial(
        currentPassword: 'not-the-password',
        newPassword: 'whatever-Strong-1!',
        currentAuthSaltBase64: base64.encode(reg.authSalt),
        currentEncSaltBase64: base64.encode(reg.encSalt),
        currentEncryptedPrivateKeyBase64:
            base64.encode(reg.encryptedPrivateKey),
      ),
      throwsA(isA<ChangePasswordWrongCurrentException>()),
    );
  });
}
