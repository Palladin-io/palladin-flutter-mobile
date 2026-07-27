import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/approval/data/services/grant_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

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
    'grant payload is revision-bound, narrowed and uses a fresh GrantDEK',
    () async {
      final crypto = sodium;
      if (crypto == null) {
        markTestSkipped('libsodium unavailable');
        return;
      }
      final envelopes = VaultProtocolEnvelopeService(
        sodiumLoader: () async => crypto,
      );
      final service = GrantCryptoService(
        sodiumLoader: () async => crypto,
        envelopes: envelopes,
      );
      final agent = crypto.crypto.box.keyPair();
      final policy = AgentVisibilityPolicy(
        discoverable: true,
        fields: const {
          'username': AgentFieldAccess.onGrantValue,
          'totp': AgentFieldAccess.onGrantDerived,
        },
      );
      Future<Map<String, dynamic>> produce() => service.produceProtocolEnvelope(
        organizationId: '11111111-1111-4111-8111-111111111111',
        vaultId: '22222222-2222-4222-8222-222222222222',
        grantId: '77777777-7777-4777-8777-777777777777',
        agentId: '55555555-5555-4555-8555-555555555555',
        entryId: '33333333-3333-4333-8333-333333333333',
        entryRevision: '9',
        memberKeyGeneration: 4,
        recipientAgentKeyVersion: 3,
        agentPublicKey: base64.encode(agent.publicKey),
        approvedMethods: 1,
        type: EntryType.credential,
        agentLabel: 'Mail',
        description: '',
        content: const {
          'username': 'ada',
          'totp': 'otpauth://totp/example?secret=SECRET',
        },
        policy: policy,
        approvedFieldIds: const ['totp'],
        remainingUses: 5,
      );
      final first = await produce();
      final second = await produce();
      expect(first['entryRevision'], '9');
      expect(first['remainingUses'], 5);
      expect(first.containsKey('expiresAt'), isFalse);
      expect(first['fieldIds'], ['totp']);
      expect(
        first['agentWrappedGrantDek'],
        isNot(second['agentWrappedGrantDek']),
      );
      expect(first['ciphertext'], isNot(second['ciphertext']));

      final grantKey = await envelopes.openPackage(
        ciphertext: VaultProtocolBytes.base64UrlDecode(
          first['agentWrappedGrantDek'] as String,
        ),
        recipientPublicKey: agent.publicKey,
        recipientPrivateKey: agent.secretKey.extractBytes(),
      );
      final context = <String, Object?>{
        'organizationId': first['organizationId'],
        'vaultId': first['vaultId'],
        'entryId': first['entryId'],
        'grantId': first['grantId'],
        'agentId': '55555555-5555-4555-8555-555555555555',
        'grantEnvelopeRevision': first['grantEnvelopeRevision'],
        'entryRevision': first['entryRevision'],
        'grantKeyVersion': 1,
        'approvedMethods': 1,
        'useLimit': 5,
        'recipientAgentKeyVersion': 3,
        'recipientAgentKeyFingerprint': first['agentKeyFingerprint'],
        'header': {
          'protocolVersion': 2,
          'algorithmSuite': 1,
          'resourceKind': 4,
          'projectionKind': 6,
          'resourceRevision': '1',
          'keyVersion': 1,
          'memberKeyGeneration': 4,
          'nonce': first['nonce'],
        },
        'ciphertext': first['ciphertext'],
      };
      final opened = await envelopes.decrypt(
        profile: VaultAadProfile.grantPayload,
        envelope: context,
        key: grantKey,
        expected: VaultEnvelopeExpectations(
          aadContext: context,
          minimumMemberKeyGeneration: 4,
        ),
      );
      final payload = jsonDecode(utf8.decode(opened)) as Map<String, dynamic>;
      final totp = (payload['fields'] as Map)['totp'] as Map;
      expect(totp['access'], 'onGrantDerived');
      expect(totp['value'], contains('secret=SECRET'));
      grantKey.fillRange(0, grantKey.length, 0);
      opened.fillRange(0, opened.length, 0);
      agent.dispose();

      expect(
        () => service.produceProtocolEnvelope(
          organizationId: '11111111-1111-4111-8111-111111111111',
          vaultId: '22222222-2222-4222-8222-222222222222',
          grantId: '77777777-7777-4777-8777-777777777777',
          agentId: '55555555-5555-4555-8555-555555555555',
          entryId: '33333333-3333-4333-8333-333333333333',
          entryRevision: '9',
          memberKeyGeneration: 4,
          recipientAgentKeyVersion: 3,
          agentPublicKey: base64.encode(Uint8List(32)),
          approvedMethods: 1,
          type: EntryType.credential,
          agentLabel: 'Mail',
          description: '',
          content: const {'password': 'secret'},
          policy: policy,
          approvedFieldIds: const ['password'],
        ),
        throwsFormatException,
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
