import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/asymmetric_keys.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_contract.dart';
import 'package:mobile_palladin/core/crypto/x25519_key_wrapper.dart';
import 'package:mobile_palladin/features/approval/data/services/encrypted_reason_crypto_service.dart';
import 'package:mobile_palladin/features/approval/domain/entities/encrypted_reason.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

String _base64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Future<SodiumSumo?> _loadSodium() async {
  try {
    final configured = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    if (configured != null) {
      return await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open(configured),
      );
    }
    if (Platform.isLinux) {
      return await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open('libsodium.so'),
      );
    }
    return await SodiumSumoInit.init();
  } catch (_) {
    return null;
  }
}

void main() {
  test('encrypted reason transcript matches backend and Rust protocol vector', () {
    final fingerprint = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final reason = EncryptedReason(
      descriptor: {
        'protocolVersion': 2,
        'cryptoSuiteId': 'palladin-vault-xchacha-v1',
        'purpose': 9,
        'scope': {
          'organizationId': '11111111-1111-4111-8111-111111111111',
          'vaultId': '22222222-2222-4222-8222-222222222222',
          'entryId': '33333333-3333-4333-8333-333333333333',
          'grantOrRequestId': '77777777-7777-4777-8777-777777777777',
          'agentId': '55555555-5555-4555-8555-555555555555',
          'memberId': null,
        },
        'resourceRevision': '1',
        'keyVersion': 1,
        'memberKeyGeneration': 4,
        'binding': {
          'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
          'recipientKeyVersion': 4,
          'recipientKeyFingerprint': _base64Url(fingerprint),
          'requestedMethods': 1,
        },
      },
      encodedSuitePayload: _base64Url(Uint8List(40)..fillRange(0, 40, 0x11)),
      wrappedReasonDek: {
        'descriptor': {
          'protocolVersion': 2,
          'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
          'purpose': 3,
        },
        'encodedSealedKeyPackage': _base64Url(
          Uint8List(120)..fillRange(0, 120, 0x22),
        ),
      },
      agentSignature: _base64Url(Uint8List(64)),
    );

    final transcript = EncryptedReasonCryptoService().signatureTranscript(
      reason,
    );
    addTearDown(() => transcript.fillRange(0, transcript.length, 0));

    expect(
      _hex(transcript),
      '504c444e56325349473a454e435259505445442d524541534f4e3a0002'
      '504c444e454e56320002001970616c6c6164696e2d7661756c742d786368616368612d7631'
      '0009001f1111111111114111811111111111111122222222222242228222222222222222'
      '3333333333334333833333333333333377777777777747778777777777777777'
      '555555555555455585555555555555550000000000000001000000010100000004'
      '001d70616c6c6164696e2d7832353531392d7365616c65642d626f782d7631'
      '00000004000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f0001'
      '1111111111111111111111111111111111111111111111111111111111111111'
      '1111111111111111'
      '001d70616c6c6164696e2d7832353531392d7365616c65642d626f782d7631'
      '2222222222222222222222222222222222222222222222222222222222222222'
      '2222222222222222222222222222222222222222222222222222222222222222'
      '2222222222222222222222222222222222222222222222222222222222222222'
      '222222222222222222222222222222222222222222222222',
    );
  });

  test(
    'parses the backend named reason wrapper contract before crypto',
    () async {
      final fingerprint = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final reason = EncryptedReason(
        descriptor: {
          'protocolVersion': 2,
          'cryptoSuiteId': 'palladin-vault-xchacha-v1',
          'purpose': 'encryptedReason',
          'scope': {
            'organizationId': '11111111-1111-4111-8111-111111111111',
            'vaultId': '22222222-2222-4222-8222-222222222222',
            'entryId': '33333333-3333-4333-8333-333333333333',
            'grantOrRequestId': '77777777-7777-4777-8777-777777777777',
            'agentId': '55555555-5555-4555-8555-555555555555',
            'memberId': null,
          },
          'resourceRevision': '1',
          'keyVersion': 1,
          'memberKeyGeneration': 4,
          'binding': {
            'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
            'recipientKeyVersion': 4,
            'recipientKeyFingerprint': _base64Url(fingerprint),
            'requestedMethods': 1,
          },
        },
        encodedSuitePayload: _base64Url(Uint8List(40)..fillRange(0, 40, 0x11)),
        wrappedReasonDek: {
          'descriptor': {
            'protocolVersion': 2,
            'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
            'purpose': 'reasonDek',
            'scope': {
              'organizationId': '11111111-1111-4111-8111-111111111111',
              'vaultId': '22222222-2222-4222-8222-222222222222',
              'entryId': '33333333-3333-4333-8333-333333333333',
              'grantOrRequestId': '77777777-7777-4777-8777-777777777777',
              'agentId': '55555555-5555-4555-8555-555555555555',
              'memberId': null,
            },
            'resourceRevision': '1',
            'wrappedKeyVersion': 1,
            'memberKeyGeneration': 4,
            'recipientKeyKind': 'vaultMessageX25519',
            'recipientKeyVersion': 4,
            'recipientFingerprint': _base64Url(fingerprint),
            'parentDescriptorHash': _base64Url(Uint8List(32)),
          },
          'encodedSealedKeyPackage': _base64Url(
            Uint8List(120)..fillRange(0, 120, 0x22),
          ),
        },
        agentSignature: _base64Url([0]),
      );

      await expectLater(
        () => EncryptedReasonCryptoService().verifyAndOpenKey(
          reason: reason,
          signingPublicKey: Uint8List(32),
          recipientPrivateKey: Uint8List(32),
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('awaits ReasonDEK opening before zeroing the sealed package', () async {
    final sodium = await _loadSodium();
    if (sodium == null) {
      if (Platform.environment['CI'] == 'true') {
        fail('CI requires a loadable libsodium for approval protocol tests');
      }
      markTestSkipped('libsodium unavailable');
      return;
    }

    const organizationId = '11111111-1111-4111-8111-111111111111';
    const vaultId = '22222222-2222-4222-8222-222222222222';
    const entryId = '33333333-3333-4333-8333-333333333333';
    const agentId = '55555555-5555-4555-8555-555555555555';
    const grantId = '77777777-7777-4777-8777-777777777777';
    const generation = 4;
    const keyVersion = 3;
    final recipient = sodium.crypto.box.keyPair();
    final signer = sodium.crypto.sign.keyPair();
    final recipientPrivateKey = recipient.secretKey.extractBytes();
    final reasonKey = sodium.randombytes.buf(32);
    Uint8List? opened;
    Uint8List? transcript;
    try {
      final fingerprint = vaultPublicKeyFingerprint(
        VaultPublicKeyKind.vaultMessageX25519,
        recipient.publicKey,
      );
      final scope = EnvelopeScope(
        organizationId: EnvelopeId.parse(organizationId),
        vaultId: EnvelopeId.parse(vaultId),
        entryId: EnvelopeId.parse(entryId),
        grantOrRequestId: EnvelopeId.parse(grantId),
        agentId: EnvelopeId.parse(agentId),
      );
      final descriptor = EnvelopeDescriptor(
        purpose: EnvelopePurpose.reason,
        scope: scope,
        resourceRevision: 1,
        keyVersion: 1,
        memberKeyGeneration: generation,
        purposeData: ReasonPurposeData(
          agentMessageKeyVersion: keyVersion,
          recipientFingerprint: fingerprint,
          methods: 2,
        ),
      );
      final wrapper = WrapperContext(
        purpose: WrapperPurpose.reasonDek,
        scope: scope,
        resourceRevision: 1,
        wrappedKeyVersion: 1,
        memberKeyGeneration: generation,
        recipientKeyKind: VaultPublicKeyKind.vaultMessageX25519.id,
        recipientKeyVersion: keyVersion,
        recipientFingerprint: fingerprint,
        parentDescriptorHash: WrapperContext.hashParent(descriptor),
      );
      final sealed =
          await X25519SealedBoxKeyWrapper(
            sodiumLoader: () async => sodium,
          ).seal(
            key: reasonKey,
            context: wrapper,
            recipient: X25519PublicKey(recipient.publicKey),
          );
      final unsigned = EncryptedReason(
        descriptor: {
          'protocolVersion': 2,
          'cryptoSuiteId': 'palladin-vault-xchacha-v1',
          'purpose': 'encryptedReason',
          'scope': {
            'organizationId': organizationId,
            'vaultId': vaultId,
            'entryId': entryId,
            'grantOrRequestId': grantId,
            'agentId': agentId,
            'memberId': null,
          },
          'resourceRevision': '1',
          'keyVersion': 1,
          'memberKeyGeneration': generation,
          'binding': {
            'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
            'recipientKeyVersion': keyVersion,
            'recipientKeyFingerprint': _base64Url(fingerprint),
            'requestedMethods': 2,
          },
        },
        encodedSuitePayload: _base64Url(Uint8List(40)),
        wrappedReasonDek: {
          'descriptor': {
            'protocolVersion': 2,
            'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
            'purpose': 'reasonDek',
            'scope': {
              'organizationId': organizationId,
              'vaultId': vaultId,
              'entryId': entryId,
              'grantOrRequestId': grantId,
              'agentId': agentId,
              'memberId': null,
            },
            'resourceRevision': '1',
            'wrappedKeyVersion': 1,
            'memberKeyGeneration': generation,
            'recipientKeyKind': 'vaultMessageX25519',
            'recipientKeyVersion': keyVersion,
            'recipientFingerprint': _base64Url(fingerprint),
            'parentDescriptorHash': _base64Url(wrapper.parentDescriptorHash!),
          },
          'encodedSealedKeyPackage': _base64Url(sealed),
        },
        agentSignature: '',
      );
      final service = EncryptedReasonCryptoService(
        sodiumLoader: () async => sodium,
      );
      transcript = service.signatureTranscript(unsigned);
      final signature = sodium.crypto.sign.detached(
        message: transcript,
        secretKey: signer.secretKey,
      );
      final signed = EncryptedReason(
        descriptor: unsigned.descriptor,
        encodedSuitePayload: unsigned.encodedSuitePayload,
        wrappedReasonDek: unsigned.wrappedReasonDek,
        agentSignature: _base64Url(signature),
      );

      opened = await service.verifyAndOpenKey(
        reason: signed,
        signingPublicKey: signer.publicKey,
        recipientPrivateKey: recipientPrivateKey,
      );

      expect(opened, orderedEquals(reasonKey));
      sealed.fillRange(0, sealed.length, 0);
      signature.fillRange(0, signature.length, 0);
      fingerprint.fillRange(0, fingerprint.length, 0);
    } finally {
      opened?.fillRange(0, opened.length, 0);
      transcript?.fillRange(0, transcript.length, 0);
      reasonKey.fillRange(0, reasonKey.length, 0);
      recipientPrivateKey.fillRange(0, recipientPrivateKey.length, 0);
      recipient.dispose();
      signer.dispose();
    }
  });
}
