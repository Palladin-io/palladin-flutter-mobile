import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/recovery/data/models/recover_account_request.dart';
import 'package:mobile_palladin/features/recovery/data/services/recovery_crypto_service.dart';
import 'package:mobile_palladin/features/recovery/domain/recovery_exceptions.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

Future<SodiumSumo> _loadSodium() {
  final configured = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
  if (configured != null || Platform.isLinux) {
    return sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(configured ?? 'libsodium.so'),
    );
  }
  return SodiumSumoInit.init();
}

Uint8List _decode(String value) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));

void main() {
  final vectors =
      jsonDecode(
            File(
              'test/fixtures/account-recovery-challenge-v1/vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final userId = vectors['userId'] as String;
  late RecoveryCryptoService service;

  setUpAll(() async {
    final sodium = await _loadSodium();
    service = RecoveryCryptoService(sodiumLoader: () async => sodium);
  });

  Uint8List privateKey() => _decode(vectors['recipientPrivateKey'] as String);

  test('opens the valid vector into the 32-byte recovery proof', () async {
    final valid = vectors['valid'] as Map<String, dynamic>;
    final key = privateKey();

    final proof = await service.openRecoveryChallenge(
      sealedChallenge: valid['sealedChallenge'] as String,
      sessionUserId: userId,
      privateKey: key,
    );

    expect(proof, _decode(valid['recoveryProof'] as String));
    expect(key, _decode(vectors['recipientPrivateKey'] as String));
  });

  for (final negative in (vectors['negative'] as List).cast<Map>()) {
    test('rejects ${negative['name']}', () async {
      await expectLater(
        service.openRecoveryChallenge(
          sealedChallenge: negative['sealedChallenge'] as String,
          sessionUserId: userId,
          privateKey: privateKey(),
        ),
        throwsA(isA<RecoveryChallengeException>()),
      );
    });
  }

  test('binds the proof to the authenticated session user', () async {
    await expectLater(
      service.openRecoveryChallenge(
        sealedChallenge:
            (vectors['valid'] as Map<String, dynamic>)['sealedChallenge']
                as String,
        sessionUserId: '00112233-4455-4677-8899-aabbccddeeff',
        privateKey: privateKey(),
      ),
      throwsA(isA<RecoveryChallengeException>()),
    );
  });

  test('rejects a malformed session user id or private key', () async {
    final sealed =
        (vectors['valid'] as Map<String, dynamic>)['sealedChallenge'] as String;
    for (final (id, key) in [
      ('not-a-uuid', privateKey()),
      (userId, Uint8List(31)),
    ]) {
      await expectLater(
        service.openRecoveryChallenge(
          sealedChallenge: sealed,
          sessionUserId: id,
          privateKey: key,
        ),
        throwsA(isA<RecoveryChallengeException>()),
      );
    }
  });

  test('recovery request carries the unpadded base64url proof', () {
    final proof = _decode(
      (vectors['valid'] as Map<String, dynamic>)['recoveryProof'] as String,
    );
    final request = RecoverAccountRequest(
      baseCredentialRevision: 1,
      basePrivateKeyWrapRevision: 1,
      newKdfSalt: Uint8List(16),
      newEncryptedPrivateKey: Uint8List(48),
      newRecoverySalt: Uint8List(16),
      newEncryptedPrivateKeyByRecovery: Uint8List(48),
      recoveryProof: proof,
    );

    expect(
      request.toJson()['recoveryProof'],
      (vectors['valid'] as Map<String, dynamic>)['recoveryProof'],
    );
    request.wipeSecrets();
    expect(proof, everyElement(0));
  });
}
