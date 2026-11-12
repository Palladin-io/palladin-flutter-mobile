import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/data/services/password_auth_crypto_service.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;

void main() {
  test('password authentication accepts only the frozen v1 profile', () {
    expect(IdentityKdfProfile.securityVersion, 1);
    expect(IdentityKdfProfile.id, 'identity-argon2id-password-v1');
    expect(IdentityKdfProfile.memoryKiB, 32768);
    expect(IdentityKdfProfile.iterations, 2);
    expect(IdentityKdfProfile.parallelism, 1);
    expect(IdentityKdfProfile.outputBytes, 32);
  });

  test('current auth credential matches the pinned login vector', () async {
    final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    if (library == null || library.isEmpty) {
      markTestSkipped('PALLADIN_LIBSODIUM_PATH is not configured');
      return;
    }
    final sodium = await sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(library),
    );
    final credential = await PasswordAuthCryptoService(
      identityKdfService: IdentityKdfService(sodiumLoader: () async => sodium),
      sodiumLoader: () async => sodium,
    ).deriveCurrentAuthCredential(
      password: 'Pąssw🔐rd-密碼-v1',
      accountId: '00112233-4455-4677-8899-aabbccddeeff',
      kdfSaltBase64: 'AAECAwQFBgcICQoLDA0ODw',
    );

    expect(
      base64Url.encode(credential).replaceAll('=', ''),
      'aRKTmLFcaSbzQy83MTRpf5PfLSjeBLGQP4HVpEudV7I',
    );
  });
}
