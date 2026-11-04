import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_contract.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_suite.dart';
import 'package:mobile_palladin/core/crypto/kem/xwing.dart';
import 'package:mobile_palladin/core/crypto/recipient_key_wrapper.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:sodium/sodium_sumo.dart';

Future<SodiumSumo?> _loadSodium() async {
  try {
    return await SodiumSumoInit.init();
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _object(Map value) => value.cast<String, Object?>();

void main() {
  late SodiumSumo? sodium;
  setUpAll(() async {
    sodium = await _loadSodium();
    if (sodium == null && Platform.environment['CI'] == 'true') {
      fail('CI requires a loadable libsodium for approval protocol tests');
    }
  });

  test(
    'encrypted reason authenticates frozen scope and rejects substitutions',
    () async {
      final crypto = sodium;
      if (crypto == null) {
        markTestSkipped('libsodium unavailable');
        return;
      }
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/vault_protocol_2/vectors/envelopes.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final vector = (fixture['aeadVectors'] as List).cast<Map>().singleWhere(
        (item) => item['id'] == 'encrypted-reason',
      );
      final envelope = _object(vector['envelope'] as Map);
      final signatures =
          jsonDecode(
                File(
                  'test/fixtures/vault_protocol_2/vectors/signatures.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final signatureVector = (signatures['vectors'] as List)
          .cast<Map>()
          .singleWhere((item) => item['id'] == 'encrypted-reason');
      final envelopeService = VaultProtocolEnvelopeService(
        sodiumLoader: () async => crypto,
      );
      final signatureService = VaultProtocolSignatureService(
        sodiumLoader: () async => crypto,
      );
      final unsigned = Map<String, Object?>.from(envelope)
        ..remove('agentSignature');
      expect(
        await signatureService.verify(
          domainPrefix: 'PLDNV2SIG:ENCRYPTED-REASON:',
          unsignedObject: unsigned,
          signature: envelope['agentSignature']! as String,
          publicKey: VaultProtocolBytes.hex(
            signatureVector['publicKeyHex']! as String,
          ),
        ),
        isTrue,
      );
      final plaintext = await envelopeService.decrypt(
        profile: VaultAadProfile.encryptedReason,
        envelope: envelope,
        key: VaultProtocolBytes.hex(vector['decryptionKeyHex']! as String),
        expected: VaultEnvelopeExpectations(
          aadContext: envelope,
          minimumMemberKeyGeneration: 4,
        ),
      );
      expect(utf8.decode(plaintext), vector['plaintextCanonical']);
      plaintext.fillRange(0, plaintext.length, 0);

      final mutations = <Map<String, Object?> Function()>[
        () => {
          ...envelope,
          'organizationId': '99999999-9999-4999-8999-999999999999',
        },
        () => {...envelope, 'vaultId': '99999999-9999-4999-8999-999999999999'},
        () => {...envelope, 'entryId': '99999999-9999-4999-8999-999999999999'},
        () => {
          ...envelope,
          'grantRequestId': '99999999-9999-4999-8999-999999999999',
        },
        () => {...envelope, 'agentId': '99999999-9999-4999-8999-999999999999'},
        () => {...envelope, 'requestedMethods': 3},
        () => {
          ...envelope,
          'recipientAgentMessageKeyFingerprint':
              'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        },
        () => {
          ...envelope,
          'header': {
            ..._object(envelope['header'] as Map),
            'projectionKind': 6,
          },
        },
        () => {...envelope, 'ciphertext': '${envelope['ciphertext']}A'},
      ];
      for (final mutate in mutations) {
        final tampered = mutate();
        final tamperedUnsigned = Map<String, Object?>.from(tampered)
          ..remove('agentSignature');
        final valid = await signatureService.verify(
          domainPrefix: 'PLDNV2SIG:ENCRYPTED-REASON:',
          unsignedObject: tamperedUnsigned,
          signature: envelope['agentSignature']! as String,
          publicKey: VaultProtocolBytes.hex(
            signatureVector['publicKeyHex']! as String,
          ),
        );
        expect(valid, isFalse);
      }
    },
  );

  test(
    'canonical grant preserves expiry precision and opens for the Agent',
    () async {
      final crypto = sodium;
      if (crypto == null) {
        markTestSkipped('libsodium unavailable');
        return;
      }
      const organizationId = '11111111-1111-4111-8111-111111111111';
      const vaultId = '22222222-2222-4222-8222-222222222222';
      const entryId = '33333333-3333-4333-8333-333333333333';
      const agentId = '55555555-5555-4555-8555-555555555555';
      const grantId = '77777777-7777-4777-8777-777777777777';
      const fieldIds = ['credential.totp'];
      const payload = {
        'schema': 'palladin.grant-payload.v2',
        'entryType': 'credential',
        'fields': [
          {
            'id': 'credential.totp',
            'kind': 'totp',
            'mode': 'derived',
            'value': {
              'source': 'totp',
              'secret': 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
              'algorithm': 'SHA1',
              'digits': 6,
              'period': 30,
            },
          },
        ],
      };
      final expiry = DateTime.utc(2026, 8, 8, 12, 34, 56, 123, 456);
      final xwing = XWing(crypto);
      final agentPrivateKey = xwing.generateSeed();
      final agentPublicKey = xwing.publicKeyFromSeed(agentPrivateKey);
      final fingerprint = recipientFingerprint(
        WrapperSuite.xwingV1,
        RecipientKeyKind.agentEncryption.id,
        agentPublicKey,
      );
      final commitment = computeFieldSetCommitment(fieldIds);
      Uint8List? grantKey;
      Uint8List? opened;
      try {
        final service = EntryV2CryptoService(sodiumLoader: () async => crypto);
        final envelope = await service.sealGrant(
          organizationId: organizationId,
          vaultId: vaultId,
          entryId: entryId,
          grantId: grantId,
          agentId: agentId,
          entryRevision: 7,
          memberKeyGeneration: 4,
          agentPublicKey: agentPublicKey,
          agentKeySuite: WrapperSuite.xwingV1,
          recipientKeyVersion: 3,
          approvedMethods: 2,
          deliveryPolicy: 0,
          fieldIds: fieldIds,
          grantPayload: payload,
          expiresAt: expiry,
        );
        final descriptorJson = Map<String, dynamic>.from(
          envelope['descriptor']! as Map,
        );
        final binding = Map<String, dynamic>.from(
          descriptorJson['binding'] as Map,
        );
        final serializedScope = Map<String, dynamic>.from(
          descriptorJson['scope'] as Map,
        );
        expect(serializedScope['organizationId'], organizationId);
        expect(serializedScope['vaultId'], vaultId);
        expect(serializedScope['entryId'], entryId);
        expect(serializedScope['grantOrRequestId'], grantId);
        expect(serializedScope['agentId'], agentId);
        expect(serializedScope['memberId'], isNull);
        expect(binding['expiresAt'], expiry.toIso8601String());
        expect(binding['wrapperSuiteId'], 'palladin-xwing-v1');
        expect(
          (envelope['wrappedGrantDek']! as Map)['descriptor']['wrapperSuiteId'],
          'palladin-xwing-v1',
        );

        final scope = EnvelopeScope(
          organizationId: EnvelopeId.parse(organizationId),
          vaultId: EnvelopeId.parse(vaultId),
          entryId: EnvelopeId.parse(entryId),
          grantOrRequestId: EnvelopeId.parse(grantId),
          agentId: EnvelopeId.parse(agentId),
        );
        final expiryMicros = expiry.microsecondsSinceEpoch;
        final descriptor = EnvelopeDescriptor(
          purpose: EnvelopePurpose.grant,
          scope: scope,
          resourceRevision: 1,
          keyVersion: 1,
          memberKeyGeneration: 4,
          purposeData: GrantPurposeData(
            wrapperSuite: WrapperSuite.xwingV1,
            entryRevision: 7,
            recipientKeyVersion: 3,
            recipientFingerprint: fingerprint,
            methods: 2,
            deliveryPolicy: 0,
            fieldSetCommitment: commitment,
            expiresAtSeconds: expiryMicros ~/ Duration.microsecondsPerSecond,
            expiresAtNanoseconds:
                (expiryMicros % Duration.microsecondsPerSecond) * 1000,
          ),
        );
        final wrapper = WrapperContext(
          suiteId: WrapperSuite.xwingV1,
          purpose: WrapperPurpose.grantDek,
          scope: scope,
          resourceRevision: 1,
          wrappedKeyVersion: 1,
          memberKeyGeneration: 4,
          recipientKeyVersion: 3,
          recipientFingerprint: fingerprint,
          parentDescriptorHash: WrapperContext.hashParent(descriptor),
        );
        final wrappedJson = Map<String, dynamic>.from(
          envelope['wrappedGrantDek']! as Map,
        );
        grantKey = await RecipientKeyWrapper(sodiumLoader: () async => crypto)
            .open(
              wrapped: VaultProtocolBytes.base64UrlDecode(
                wrappedJson['encodedSealedKeyPackage'] as String,
              ),
              context: wrapper,
              recipientSecretKey: agentPrivateKey,
            );
        opened =
            await XChaChaVaultEnvelopeSuite(
              sodiumLoader: () async => crypto,
            ).open(
              descriptor: descriptor,
              rootKey: grantKey,
              payload: EncodedSuitePayload.fromBase64Url(
                envelope['encodedSuitePayload']! as String,
              ),
            );

        expect(jsonDecode(utf8.decode(opened)), payload);
      } finally {
        grantKey?.fillRange(0, grantKey.length, 0);
        opened?.fillRange(0, opened.length, 0);
        agentPrivateKey.fillRange(0, agentPrivateKey.length, 0);
        fingerprint.fillRange(0, fingerprint.length, 0);
        commitment.fillRange(0, commitment.length, 0);
      }
    },
  );

  test(
    'a legacy Agent key receives no new grant (key-migration-pending)',
    () async {
      final crypto = sodium;
      if (crypto == null) {
        markTestSkipped('libsodium unavailable');
        return;
      }
      final agent = crypto.crypto.box.keyPair();
      addTearDown(agent.dispose);
      await expectLater(
        () => EntryV2CryptoService(sodiumLoader: () async => crypto).sealGrant(
          organizationId: '11111111-1111-4111-8111-111111111111',
          vaultId: '22222222-2222-4222-8222-222222222222',
          entryId: '33333333-3333-4333-8333-333333333333',
          grantId: '77777777-7777-4777-8777-777777777777',
          agentId: '55555555-5555-4555-8555-555555555555',
          entryRevision: 1,
          memberKeyGeneration: 1,
          agentPublicKey: agent.publicKey,
          agentKeySuite: WrapperSuite.x25519SealedBoxV1,
          recipientKeyVersion: 1,
          approvedMethods: 1,
          deliveryPolicy: 0,
          fieldIds: const ['credential.totp'],
          grantPayload: const {'schema': 'palladin.grant-payload.v2'},
        ),
        throwsA(isA<KeyMigrationPendingException>()),
      );
    },
  );

  test('Script source and refs retain runtime-only semantics', () {
    final policy = AgentVisibilityPolicy(
      discoverable: true,
      fields: const {
        'script': AgentFieldAccess.onGrantRuntime,
        'refs': AgentFieldAccess.onGrantRuntime,
      },
    );
    expect(policy.fields['script'], AgentFieldAccess.onGrantRuntime);
    expect(policy.fields['refs'], AgentFieldAccess.onGrantRuntime);
    expect(
      () => AgentVisibilityPolicy.fromJson(
        EntryType.script,
        {
          'discoverable': true,
          'fields': {'script': 'onGrantValue', 'refs': 'onGrantRuntime'},
        },
        content: const {'script': 'echo ok', 'refs': []},
      ),
      throwsFormatException,
    );
  });
}
