import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;

Uint8List _decode(String value) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));

String _encode(Uint8List value) => base64Url.encode(value).replaceAll('=', '');

void main() {
  group('IdentityKdfService contract', () {
    final service = IdentityKdfService();
    final salt = _decode('AAECAwQFBgcICQoLDA0ODw');

    test('matches the independent .NET HKDF vector', () {
      final outputs = service.deriveOutputsFromRoot(
        accountRoot: _decode('5NWVu_9TkyrsWRtZhENZzDYTeSUcLnMYIFGBzv_8_eg'),
        accountId: '00112233-4455-4677-8899-aabbccddeeff',
      );
      expect(
        _encode(outputs.authCredential),
        'aRKTmLFcaSbzQy83MTRpf5PfLSjeBLGQP4HVpEudV7I',
      );
      expect(
        _encode(outputs.masterKey),
        'HtGyf-Z7BvE39e66VcP2bztQ0BBKmfzvBGCp_nLiXbk',
      );
      outputs.dispose();
    });

    test('matches the pinned production Argon2id vector', () async {
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
            kdfSalt: salt,
          );
      expect(
        _encode(outputs.authCredential),
        'aRKTmLFcaSbzQy83MTRpf5PfLSjeBLGQP4HVpEudV7I',
      );
      expect(
        _encode(outputs.masterKey),
        'HtGyf-Z7BvE39e66VcP2bztQ0BBKmfzvBGCp_nLiXbk',
      );
      outputs.dispose();
    });

    test('rejects unsupported metadata before loading Argon2', () {
      var sodiumLoads = 0;
      final guarded = IdentityKdfService(
        sodiumLoader: () {
          sodiumLoads += 1;
          throw StateError('must not load');
        },
      );
      expect(
        () => guarded.assertSupported(
          const IdentityKdfMetadata(
            securityVersion: 4,
            minimumSecurityVersion: 4,
            profileId: 'future',
            kdfSalt: 'AAAAAAAAAAAAAAAAAAAAAA',
            credentialRevision: 1,
            privateKeyWrapRevision: 1,
          ),
        ),
        throwsA(
          isA<UnsupportedIdentityKdfException>().having(
            (error) => error.code,
            'code',
            'upgrade-required',
          ),
        ),
      );
      expect(sodiumLoads, 0);
    });

    test('freezes the password-only v1 profile constants', () {
      expect(IdentityKdfProfile.securityVersion, 1);
      expect(IdentityKdfProfile.id, 'identity-argon2id-password-v1');
      expect(IdentityKdfProfile.memoryKiB, 32768);
      expect(IdentityKdfProfile.iterations, 2);
      expect(IdentityKdfProfile.parallelism, 1);
    });
  });
}
