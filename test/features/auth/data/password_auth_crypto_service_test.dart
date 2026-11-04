import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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

  test(
    'the version-1 source profile matches the pinned login vector',
    () async {
      final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
      if (library == null || library.isEmpty) {
        markTestSkipped('PALLADIN_LIBSODIUM_PATH is not configured');
        return;
      }
      final sodium = await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open(library),
      );
      final outputs = await IdentityKdfService(sodiumLoader: () async => sodium)
          .derive(
            password: 'Pąssw🔐rd-密碼-v1',
            accountId: '00112233-4455-4677-8899-aabbccddeeff',
            kdfSalt: Uint8List.fromList(
              base64Url.decode('AAECAwQFBgcICQoLDA0ODw=='),
            ),
          );
      final credential = outputs.authCredential;
      expect(
        base64Url.encode(credential).replaceAll('=', ''),
        'aRKTmLFcaSbzQy83MTRpf5PfLSjeBLGQP4HVpEudV7I',
      );
    },
  );
}
