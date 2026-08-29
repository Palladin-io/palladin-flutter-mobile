import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/asymmetric_keys.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_contract.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_suite.dart';
import 'package:mobile_palladin/core/crypto/x25519_key_wrapper.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/models/vault_rotation_models.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;

void main() {
  test('opens the canonical Agent-message private-key contract', () async {
    final suite = _RecordingSuite(Uint8List(32));
    final service = VaultRotationCryptoService(
      cryptoSuites: CryptoSuiteRegistry(suites: [suite]),
    );
    final opened = await service.openCanonicalAgentMessagePrivateKey(
      {
        'descriptor': {
          'protocolVersion': 2,
          'cryptoSuiteId': 'palladin-vault-xchacha-v1',
          'purpose': 'vaultAgentMessagePrivateKey',
          'scope': {
            'organizationId': '11111111-1111-4111-8111-111111111111',
            'vaultId': '22222222-2222-4222-8222-222222222222',
            'entryId': null,
            'grantOrRequestId': null,
            'agentId': null,
            'memberId': null,
          },
          'resourceRevision': '1',
          'keyVersion': 3,
          'memberKeyGeneration': 4,
          'binding': {'wrappingVaultKeyVersion': 2},
        },
        'encodedSuitePayload': VaultProtocolBytes.base64UrlEncode(
          Uint8List(40),
        ),
      },
      Uint8List(32),
      expectedKeyVersion: 3,
    );

    expect(opened, hasLength(32));
    expect(suite.descriptor?.purpose, EnvelopePurpose.agentMessagePrivateByVk);
    expect(suite.descriptor?.keyVersion, 3);
    expect(
      (suite.descriptor?.purposeData as WrappingPurposeData)
          .wrappingVaultKeyVersion,
      2,
    );
  });

  test('selects canonical Vault private key from its descriptor', () {
    final message = <String, dynamic>{
      'descriptor': {'purpose': 'vaultAgentMessagePrivateKey', 'keyVersion': 3},
      'encodedSuitePayload': 'opaque',
    };
    final signing = <String, dynamic>{
      'descriptor': {
        'purpose': 'vaultManifestSigningPrivateKey',
        'keyVersion': 3,
      },
      'encodedSuitePayload': 'opaque',
    };

    expect(
      VaultRotationCryptoService.requirePrivateKeyEnvelope(
        envelopes: [message, signing],
        purpose: 'vaultAgentMessagePrivateKey',
        keyVersion: 3,
      ),
      message,
    );
  });

  test('rejects legacy flattened or ambiguous Vault private keys', () {
    expect(
      () => VaultRotationCryptoService.requirePrivateKeyEnvelope(
        envelopes: const [
          {'privateKeyKind': 1, 'privateKeyVersion': 1},
        ],
        purpose: 'vaultAgentMessagePrivateKey',
        keyVersion: 1,
      ),
      throwsFormatException,
    );
    final canonical = {
      'descriptor': {'purpose': 'vaultAgentMessagePrivateKey', 'keyVersion': 1},
    };
    expect(
      () => VaultRotationCryptoService.requirePrivateKeyEnvelope(
        envelopes: [canonical, canonical],
        purpose: 'vaultAgentMessagePrivateKey',
        keyVersion: 1,
      ),
      throwsFormatException,
    );
  });

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

  test('rejects Member Vault key outside the fetched Vault epoch', () async {
    final service = VaultRotationCryptoService(
      sodiumLoader: () async => throw StateError('sodium must not be reached'),
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
            Uint8List(32),
          ),
          'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
        },
        'encodedSealedKeyPackage': VaultProtocolBytes.base64UrlEncode(
          Uint8List(120),
        ),
      },
    };

    await expectLater(
      service.openMemberVaultKey(
        envelope,
        Uint8List(32),
        expectedOrganizationId: '11111111-1111-4111-8111-111111111111',
        expectedVaultId: '22222222-2222-4222-8222-222222222222',
        expectedVaultKeyVersion: 3,
        expectedMemberKeyGeneration: 5,
      ),
      throwsA(isA<EnvelopeException>()),
    );
  });

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

  test('seals the whole Vault key once for an active FULL grant', () async {
    final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    final sodium = await _loadSodium(library);
    if (sodium == null) {
      markTestSkipped('libsodium is unavailable on this test host');
      return;
    }
    const organizationId = '11111111-1111-4111-8111-111111111111';
    const vaultId = '22222222-2222-4222-8222-222222222222';
    const grantId = '33333333-3333-4333-8333-333333333333';
    const agentId = '44444444-4444-4444-8444-444444444444';
    final keyPair = sodium.crypto.box.keyPair();
    final privateKey = keyPair.secretKey.extractBytes();
    final fingerprint = vaultPublicKeyFingerprint(
      VaultPublicKeyKind.agentX25519,
      keyPair.publicKey,
    );
    final vaultKey = Uint8List.fromList(
      List<int>.generate(32, (index) => index + 1),
    );
    final signingPair = sodium.crypto.sign.keyPair();
    final signingPrivateKey = signingPair.secretKey.extractBytes();
    final service = VaultRotationCryptoService(
      sodiumLoader: () async => sodium,
    );
    final contract = await service.sealAgentVaultKey(
      recipient: RotationFullGrantRecipient(
        grantId: grantId,
        agentId: agentId,
        agentAccessEpoch: 7,
        recipientKeyVersion: 2,
        recipientKeyFingerprint: VaultProtocolBytes.base64UrlEncode(
          fingerprint,
        ),
        x25519PublicKey: VaultProtocolBytes.base64UrlEncode(keyPair.publicKey),
      ),
      organizationId: organizationId,
      vaultId: vaultId,
      vaultKeyVersion: 3,
      vaultKey: vaultKey,
      vaultSigningKeyVersion: 4,
      vaultSigningPrivateKey: signingPrivateKey,
    );
    final wrapped = Map<String, Object?>.from(
      contract['wrappedVaultKey']! as Map,
    );
    final descriptor = Map<String, Object?>.from(wrapped['descriptor']! as Map);

    expect(descriptor['purpose'], WrapperPurpose.agentVaultKey.id);
    expect(descriptor['resourceRevision'], '7');
    expect(descriptor['wrappedKeyVersion'], 3);
    expect(descriptor['memberKeyGeneration'], isNull);
    expect(contract['vaultSigningKeyVersion'], 4);
    expect(contract['producerSignature'], isA<String>());
    final unsigned = Map<String, Object?>.from(contract)
      ..remove('producerSignature');
    expect(
      await VaultProtocolSignatureService(
        sodiumLoader: () async => sodium,
      ).verify(
        domainPrefix: 'PLDNV2SIG:AGENT-WRAPPED-VAULT-KEY:',
        unsignedObject: unsigned,
        signature: contract['producerSignature']! as String,
        publicKey: Uint8List.fromList(signingPair.publicKey),
      ),
      isTrue,
    );
    final opened =
        await X25519SealedBoxKeyWrapper(sodiumLoader: () async => sodium).open(
          wrapped: VaultProtocolBytes.base64UrlDecode(
            wrapped['encodedSealedKeyPackage']! as String,
          ),
          context: WrapperContext(
            purpose: WrapperPurpose.agentVaultKey,
            scope: EnvelopeScope(
              organizationId: EnvelopeId.parse(organizationId),
              vaultId: EnvelopeId.parse(vaultId),
              grantOrRequestId: EnvelopeId.parse(grantId),
              agentId: EnvelopeId.parse(agentId),
            ),
            resourceRevision: 7,
            wrappedKeyVersion: 3,
            recipientKeyVersion: 2,
            recipientFingerprint: fingerprint,
          ),
          recipientSecretKey: privateKey,
        );
    expect(opened, vaultKey);

    opened.fillRange(0, opened.length, 0);
    privateKey.fillRange(0, privateKey.length, 0);
    fingerprint.fillRange(0, fingerprint.length, 0);
    vaultKey.fillRange(0, vaultKey.length, 0);
    signingPrivateKey.fillRange(0, signingPrivateKey.length, 0);
    signingPair.dispose();
    keyPair.dispose();
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

final class _RecordingSuite implements ClientEnvelopeSuite {
  _RecordingSuite(this.result);

  final Uint8List result;
  EnvelopeDescriptor? descriptor;

  @override
  CryptoSuiteId get id => CryptoSuiteId.palladinVaultXChaChaV1;

  @override
  Future<Uint8List> open({
    required EnvelopeDescriptor descriptor,
    required Uint8List rootKey,
    required EncodedSuitePayload payload,
  }) async {
    this.descriptor = descriptor;
    return Uint8List.fromList(result);
  }

  @override
  Future<EncodedSuitePayload> seal({
    required EnvelopeDescriptor descriptor,
    required Uint8List rootKey,
    required Uint8List plaintext,
    Uint8List? nonce,
  }) => throw UnimplementedError();
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
