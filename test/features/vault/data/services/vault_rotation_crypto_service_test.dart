import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/asymmetric_keys.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_contract.dart';
import 'package:mobile_palladin/core/crypto/x25519_key_wrapper.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;

void main() {
  test('accepts only the canonical nested Member Vault key contract', () async {
    final service = VaultRotationCryptoService(
      sodiumLoader: () async => throw StateError('sodium-reached'),
    );
    final envelope = <String, dynamic>{
      'wrappedVaultKey': {
        'descriptor': {
          'protocolVersion': 2,
          'purpose': 'memberVaultKey',
          'scope': {
            'organizationId': '11111111-1111-4111-8111-111111111111',
            'vaultId': '22222222-2222-4222-8222-222222222222',
            'memberId': '44444444-4444-4444-8444-444444444444',
          },
          'resourceRevision': '1',
          'wrappedKeyVersion': 4,
          'memberKeyGeneration': 5,
          'recipientKeyKind': 'memberX25519',
          'recipientKeyVersion': 2,
          'recipientFingerprint': VaultProtocolBytes.base64UrlEncode(
            Uint8List.fromList(List<int>.generate(32, (index) => index + 1)),
          ),
          'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
        },
        'encodedSealedKeyPackage': VaultProtocolBytes.base64UrlEncode(
          Uint8List(120),
        ),
      },
    };

    await expectLater(
      service.openMemberVaultKey(envelope, Uint8List(32)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      service.openMemberVaultKey({
        'sealedVaultKeyPackage': 'legacy',
      }, Uint8List(32)),
      throwsA(isA<EnvelopeException>()),
    );
  });

  test(
    'rejects incomplete Member Vault key descriptors without null crashes',
    () async {
      final service = VaultRotationCryptoService(
        sodiumLoader: () async =>
            throw StateError('sodium must not be reached'),
      );
      final incomplete = <String, dynamic>{
        'wrappedVaultKey': {
          'descriptor': {
            'protocolVersion': 2,
            'purpose': 'memberVaultKey',
            'scope': {
              'organizationId': '11111111-1111-4111-8111-111111111111',
              'vaultId': '22222222-2222-4222-8222-222222222222',
              'memberId': null,
            },
            'resourceRevision': '1',
            'wrappedKeyVersion': 1,
            'memberKeyGeneration': 1,
            'recipientKeyKind': 'memberX25519',
            'recipientKeyVersion': 1,
            'recipientFingerprint': null,
            'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
          },
          'encodedSealedKeyPackage': null,
        },
      };

      await expectLater(
        service.openMemberVaultKey(incomplete, Uint8List(32)),
        throwsA(isA<EnvelopeException>()),
      );
    },
  );

  test('opens the canonical pending Member Vault key package', () async {
    final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    final sodium = await _loadSodium(library);
    if (sodium == null) {
      markTestSkipped('libsodium is unavailable on this test host');
      return;
    }
    final service = VaultRotationCryptoService(
      sodiumLoader: () async => sodium,
      envelopes: VaultProtocolEnvelopeService(sodiumLoader: () async => sodium),
      signatures: VaultProtocolSignatureService(
        sodiumLoader: () async => sodium,
      ),
    );
    final recipient = sodium.crypto.box.keyPair();
    final privateKey = recipient.secretKey.extractBytes();
    final publicKey = recipient.publicKey;
    final expectedKey = Uint8List.fromList(
      List<int>.generate(32, (index) => index + 1),
    );
    final fingerprint = vaultPublicKeyFingerprint(
      VaultPublicKeyKind.memberX25519,
      publicKey,
    );
    final context = WrapperContext(
      purpose: WrapperPurpose.memberVaultKey,
      scope: EnvelopeScope(
        organizationId: EnvelopeId.parse(
          '11111111-1111-4111-8111-111111111111',
        ),
        vaultId: EnvelopeId.parse('22222222-2222-4222-8222-222222222222'),
        memberId: EnvelopeId.parse('44444444-4444-4444-8444-444444444444'),
      ),
      resourceRevision: 1,
      wrappedKeyVersion: 4,
      memberKeyGeneration: 5,
      recipientKeyKind: VaultPublicKeyKind.memberX25519.id,
      recipientKeyVersion: 2,
      recipientFingerprint: fingerprint,
    );
    final sealed =
        await X25519SealedBoxKeyWrapper(sodiumLoader: () async => sodium).seal(
          key: expectedKey,
          context: context,
          recipient: X25519PublicKey(publicKey),
        );
    final envelope = <String, dynamic>{
      'wrappedVaultKey': {
        'descriptor': {
          'protocolVersion': 2,
          'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
          'purpose': 'memberVaultKey',
          'scope': {
            'organizationId': '11111111-1111-4111-8111-111111111111',
            'vaultId': '22222222-2222-4222-8222-222222222222',
            'memberId': '44444444-4444-4444-8444-444444444444',
          },
          'resourceRevision': '1',
          'wrappedKeyVersion': 4,
          'memberKeyGeneration': 5,
          'recipientKeyKind': 'memberX25519',
          'recipientKeyVersion': 2,
          'recipientFingerprint': VaultProtocolBytes.base64UrlEncode(
            fingerprint,
          ),
        },
        'encodedSealedKeyPackage': VaultProtocolBytes.base64UrlEncode(sealed),
      },
    };

    final key = await service.openMemberVaultKey(envelope, privateKey);

    expect(key, expectedKey);
    key.fillRange(0, key.length, 0);
    expectedKey.fillRange(0, expectedKey.length, 0);
    privateKey.fillRange(0, privateKey.length, 0);
    fingerprint.fillRange(0, fingerprint.length, 0);
    sealed.fillRange(0, sealed.length, 0);
    recipient.dispose();
  });

  test('rewraps a canonical Entry DEK into the target generation', () async {
    final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    final sodium = await _loadSodium(library);
    if (sodium == null) {
      markTestSkipped('libsodium is unavailable on this test host');
      return;
    }
    final envelopeService = VaultProtocolEnvelopeService(
      sodiumLoader: () async => sodium,
    );
    final service = VaultRotationCryptoService(
      sodiumLoader: () async => sodium,
      envelopes: envelopeService,
      signatures: VaultProtocolSignatureService(
        sodiumLoader: () async => sodium,
      ),
    );
    final root =
        jsonDecode(
              File(
                'test/fixtures/vault_protocol_2/vectors/envelopes.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final vector = (root['aeadVectors'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['id'] == 'vault-entry-key');
    final source = Map<String, dynamic>.from(vector['envelope'] as Map);
    final targetKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

    final rewrapped = await service.rewrapEntryKey(
      source,
      VaultProtocolBytes.hex(vector['decryptionKeyHex']! as String),
      targetKey,
      5,
      4,
    );
    final opened = await envelopeService.decrypt(
      profile: VaultAadProfile.entryKeyWrapper,
      envelope: rewrapped,
      key: targetKey,
      expected: VaultEnvelopeExpectations(
        aadContext: rewrapped,
        minimumMemberKeyGeneration: 5,
      ),
    );

    expect(VaultProtocolBytes.hexEncode(opened), vector['plaintextHex']);
    opened.fillRange(0, opened.length, 0);
    targetKey.fillRange(0, targetKey.length, 0);
  });
}

Future<sodium_ffi.SodiumSumo?> _loadSodium(String? library) async {
  try {
    return await sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(library ?? 'libsodium.so'),
    );
  } on ArgumentError {
    return null;
  }
}
