import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/identity/device_pairing.dart';
import 'package:mobile_palladin/core/crypto/identity/secret_key_codec.dart';
import 'package:mobile_palladin/core/crypto/kem/xwing.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../support/native_sodium.dart';

void main() {
  final v2 = readJsonFixture(
    'test/fixtures/identity-kdf-v3/v2-derivation-vectors.json',
  );
  final v3 = readJsonFixture('test/fixtures/identity-kdf-v3/vectors.json');
  late SodiumSumo sodium;

  setUpAll(() async => sodium = await loadTestSodium());

  group('identity-kdf v2 Account Secret derivation', () {
    final input = v2['input'] as Map<String, dynamic>;
    final expected = v2['expected'] as Map<String, dynamic>;
    final service = IdentityKdfService();

    test('prehash, output salt and outputs match the frozen vector', () {
      final secret = b64urlBytes(input['accountSecretBase64url'] as String);
      final salt = b64urlBytes(input['kdfSaltBase64url'] as String);
      expect(
        b64url(
          service.passwordPrehashV2(
            password: input['password'] as String,
            accountSecret: secret,
          ),
        ),
        expected['passwordPrehashBase64url'],
      );
      expect(
        b64url(
          service.outputSaltV2(
            accountId: input['accountId'] as String,
            kdfSalt: salt,
          ),
        ),
        expected['outputSaltBase64url'],
      );
      final outputs = service.deriveV2OutputsFromRoot(
        accountRoot: b64urlBytes(
          input['syntheticAccountRootBase64url'] as String,
        ),
        accountId: input['accountId'] as String,
        kdfSalt: salt,
      );
      expect(
        b64url(outputs.authCredential),
        expected['authCredentialBase64url'],
      );
      expect(b64url(outputs.masterKey), expected['masterKeyBase64url']);
    });

    test('selects profiles only from the release registry', () {
      IdentityKdfMetadata metadata(int version, String id, {int minimum = 1}) =>
          IdentityKdfMetadata(
            securityVersion: version,
            minimumSecurityVersion: minimum,
            profileId: id,
            kdfSalt: input['kdfSaltBase64url'] as String,
            credentialRevision: 1,
            privateKeyWrapRevision: 1,
          );
      expect(
        service.assertSupported(metadata(1, IdentityKdfProfile.id)),
        IdentityKdfVersion.passwordV1,
      );
      expect(
        service.assertSupported(
          metadata(2, IdentityKdfProfileV2.id, minimum: 2),
        ),
        IdentityKdfVersion.accountSecretV2,
      );
      expect(
        () => service.assertSupported(
          metadata(1, IdentityKdfProfile.id, minimum: 2),
        ),
        throwsA(isA<UnsupportedIdentityKdfException>()),
      );
      expect(
        () => service.assertSupported(metadata(2, IdentityKdfProfile.id)),
        throwsA(isA<UnsupportedIdentityKdfException>()),
      );
      expect(
        () => service.assertSupported(metadata(3, 'future', minimum: 3)),
        throwsA(
          isA<UnsupportedIdentityKdfException>().having(
            (error) => error.code,
            'code',
            'upgrade-required',
          ),
        ),
      );
    });
  });

  group('Secret Key display', () {
    final vector = v3['secretKeyDisplay'] as Map<String, dynamic>;
    final accountId = vector['accountId'] as String;
    final secret = b64urlBytes(vector['accountSecretBase64url'] as String);

    test('formats and parses equivalent inputs', () {
      expect(SecretKeyCodec.format(accountId, secret), vector['display']);
      for (final input in [
        vector['display'],
        ...vector['equivalentInputs'] as List,
      ]) {
        expect(SecretKeyCodec.parse(accountId, input as String), secret);
      }
    });

    for (final negative
        in (vector['negative'] as List).cast<Map<String, dynamic>>()) {
      test('rejects ${negative['input']} as ${negative['error']}', () {
        expect(
          () => SecretKeyCodec.parse(
            negative['accountId'] as String? ?? accountId,
            negative['input'] as String,
          ),
          throwsA(
            isA<SecretKeyFormatException>().having(
              (error) => error.error,
              'error',
              negative['error'] == 'secret-key-malformed'
                  ? SecretKeyFormatError.malformed
                  : SecretKeyFormatError.checksumMismatch,
            ),
          ),
        );
      });
    }

    test('Emergency Kit QR round-trips and is bound to the account', () {
      final kit = v3['emergencyKitQr'] as Map<String, dynamic>;
      expect(SecretKeyCodec.emergencyKitQr(accountId, secret), kit['payload']);
      expect(
        SecretKeyCodec.parseEmergencyKitQr(accountId, kit['payload'] as String),
        secret,
      );
      expect(
        () => SecretKeyCodec.parseEmergencyKitQr(
          '00112233-4455-6677-8899-aabbccddeef0',
          kit['payload'] as String,
        ),
        throwsA(isA<SecretKeyFormatException>()),
      );
      expect(
        () =>
            SecretKeyCodec.parseEmergencyKitQr(accountId, '${kit['payload']}='),
        throwsA(isA<SecretKeyFormatException>()),
      );
    });
  });

  group('device pairing v2', () {
    final vector = v3['devicePairing'] as Map<String, dynamic>;
    final accountId = vector['accountId'] as String;
    final transferId = vector['transferIdBase64url'] as String;
    final challenge = b64urlBytes(vector['challengeBase64url'] as String);
    final seed = hexBytes(vector['recipientSeedHex'] as String);
    final envelope = vector['envelope'] as Map<String, dynamic>;
    late DevicePairingCrypto crypto;
    late Uint8List publicKey;

    setUp(() {
      crypto = DevicePairingCrypto(sodiumLoader: () async => sodium);
      publicKey = XWing(sodium).publicKeyFromSeed(seed);
    });

    PairingOffer offer({String? account, Uint8List? servedChallenge}) =>
        PairingOffer.verify(
          accountId: account ?? accountId,
          transferId: transferId,
          challenge: servedChallenge ?? challenge,
          recipientPublicKey: publicKey,
          scanned: PairingQr.parse(vector['qrRecipientShows'] as String),
        );

    test('QR payloads, offer bytes and SAS match', () {
      expect(
        PairingQr.recipientShows(transferId, publicKey),
        vector['qrRecipientShows'],
      );
      expect(
        PairingQr.senderShows(transferId, challenge),
        vector['qrSenderShows'],
      );
      expect(toHex(offer().offerBytes), vector['offerBytesHex']);
      expect(offer().sas, vector['sas']);
      expect(
        offer(account: '00112233-4455-6677-8899-aabbccddeef0').sas,
        isNot(vector['sas']),
      );
    });

    test(
      'opens the vector envelope and reproduces it deterministically',
      () async {
        final wire = PairingEnvelope(
          kemCiphertext: envelope['kemCiphertext'] as String,
          ciphertext: envelope['ciphertext'] as String,
        );
        final opened = await crypto.open(
          offer: offer(),
          envelope: wire,
          recipientSeed: seed,
        );
        expect(b64url(opened), vector['accountSecretBase64url']);

        final sealed = await crypto.seal(
          confirmed: ConfirmedPairingOffer(offer()),
          recipientPublicKey: publicKey,
          accountSecret: opened,
          encapsulationRandomness: hexBytes(
            vector['encapsulationRandomnessHex'] as String,
          ),
        );
        expect(sealed.kemCiphertext, envelope['kemCiphertext']);
        expect(sealed.ciphertext, envelope['ciphertext']);
      },
    );

    test('a substituted challenge fails AEAD', () async {
      final negative = (vector['negative'] as List)[1] as Map<String, dynamic>;
      await expectLater(
        crypto.open(
          offer: offer(
            servedChallenge: b64urlBytes(
              negative['challengeBase64url'] as String,
            ),
          ),
          envelope: PairingEnvelope(
            kemCiphertext: envelope['kemCiphertext'] as String,
            ciphertext: envelope['ciphertext'] as String,
          ),
          recipientSeed: seed,
        ),
        throwsA(
          isA<DevicePairingException>().having(
            (error) => error.error,
            'error',
            DevicePairingError.aeadFailure,
          ),
        ),
      );
    });

    test('a backend-substituted recipient key creates no offer', () {
      final substituted = XWing(sodium).publicKeyFromSeed(Uint8List(32));
      expect(
        () => PairingOffer.verify(
          accountId: accountId,
          transferId: transferId,
          challenge: challenge,
          recipientPublicKey: substituted,
          scanned: PairingQr.parse(vector['qrRecipientShows'] as String),
        ),
        throwsA(
          isA<DevicePairingException>().having(
            (error) => error.error,
            'error',
            DevicePairingError.recipientKeyDigestMismatch,
          ),
        ),
      );
    });

    test('a backend-substituted challenge creates no offer', () {
      expect(
        () => PairingOffer.verify(
          accountId: accountId,
          transferId: transferId,
          challenge: Uint8List(32)..fillRange(0, 32, 0x24),
          recipientPublicKey: publicKey,
          scanned: PairingQr.parse(vector['qrSenderShows'] as String),
        ),
        throwsA(
          isA<DevicePairingException>().having(
            (error) => error.error,
            'error',
            DevicePairingError.challengeMismatch,
          ),
        ),
      );
    });

    test('rejects malformed QR payloads', () {
      for (final raw in [
        'palladin-pair:v1:r:ISEhISEhISEhISEhISEhIQ.${'A' * 43}',
        'palladin-pair:v2:r:ISEhISEhISEhISEhISEhIQ',
        'palladin-pair:v2:s:ISEhISEhISEhISEhISEhIQ.short',
      ]) {
        expect(
          () => PairingQr.parse(raw),
          throwsA(isA<DevicePairingException>()),
        );
      }
    });
  });

  group('recovery challenge v2', () {
    final vector = v3['recoveryChallenge'] as Map<String, dynamic>;

    test('opens for the session user and fails for another user', () async {
      final crypto = RecoveryChallengeV2Crypto(
        sodiumLoader: () async => sodium,
      );
      final seed = hexBytes(vector['memberSeedHex'] as String);
      final secret = await crypto.open(
        encodedPackage: vector['package'] as String,
        userId: vector['userId'] as String,
        memberSeed: seed,
      );
      expect(b64url(secret), vector['secretBase64url']);
      final other = (vector['negative'] as List).first as Map<String, dynamic>;
      await expectLater(
        crypto.open(
          encodedPackage: vector['package'] as String,
          userId: other['userId'] as String,
          memberSeed: seed,
        ),
        throwsA(isA<DevicePairingException>()),
      );
    });
  });
}
