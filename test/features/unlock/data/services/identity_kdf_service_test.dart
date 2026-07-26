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
    final accountSecret = _decode(
      'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA',
    );
    final salt = _decode('oKGio6SlpqeoqaqrrK2urw');

    test('matches the canonical framing and HKDF vector', () {
      final prehash = service.derivePasswordPrehash(
        'Pālladin 🔐',
        accountSecret,
      );
      expect(_encode(prehash), 'mgd1_1YGawbQ1UhggrVt2ME0M1CysLSXHTF3ytdUyXU');

      final outputs = service.deriveOutputsFromRoot(
        accountRoot: _decode('QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8'),
        accountId: '00112233-4455-6677-8899-aabbccddeeff',
        kdfSalt: salt,
      );
      expect(
        _encode(outputs.authCredential),
        'GfluE1P0DH4qBYvrGx8brXYLcWd-vkER1h3Pwbn5LgI',
      );
      expect(
        _encode(outputs.masterKey),
        '-H5RzHzdhlwaNS-KDaUgeHWhH-DODMBcZYeN2pUqc2k',
      );
      prehash.fillRange(0, prehash.length, 0);
      outputs.dispose();
    });

    test('matches the pinned production Argon2id vector', () async {
      final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
      final sodium = await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open(library ?? 'libsodium.so'),
      );
      final outputs = await IdentityKdfService(sodiumLoader: () async => sodium)
          .derive(
            password: 'Pālladin 🔐',
            accountSecret: accountSecret,
            accountId: '00112233-4455-6677-8899-aabbccddeeff',
            kdfSalt: salt,
          );
      expect(
        _encode(outputs.authCredential),
        'zt-K2HTHwY93TTY3rgxqUOVCOkHYU4HOlqg6ak3dsJU',
      );
      expect(
        _encode(outputs.masterKey),
        'jBJz-TGOc8XKJmi1fNxcfQKNIVqTLyPIh4RHXk6jVCo',
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
            securityVersion: 3,
            minimumSecurityVersion: 3,
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

    test('rejects password over the UTF-8 byte limit before Argon2', () {
      expect(
        () => service.derivePasswordPrehash(
          List<String>.filled(513, 'ą').join(),
          accountSecret,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
