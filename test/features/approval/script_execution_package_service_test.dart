import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_contract.dart';
import 'package:mobile_palladin/core/crypto/x25519_key_wrapper.dart';
import 'package:mobile_palladin/features/approval/data/services/script_execution_package_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';
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

void main() {
  test('four references produce one complete Agent-openable package', () async {
    final sodium = await _loadSodium();
    if (sodium == null) {
      markTestSkipped('libsodium unavailable');
      return;
    }
    const organizationId = '11111111-1111-4111-8111-111111111111';
    const vaultId = '22222222-2222-4222-8222-222222222222';
    const scriptId = '33333333-3333-4333-8333-333333333333';
    const grantId = '44444444-4444-4444-8444-444444444444';
    const agentId = '55555555-5555-4555-8555-555555555555';
    const referenceIds = [
      '66666666-6666-4666-8666-666666666661',
      '66666666-6666-4666-8666-666666666662',
      '66666666-6666-4666-8666-666666666663',
      '66666666-6666-4666-8666-666666666664',
    ];
    const environmentNames = ['DB_HOST', 'DB_USER', 'DB_PASSWORD', 'DB_PORT'];
    const fieldIds = [
      'credential.url',
      'credential.username',
      'credential.password',
      'key.value',
    ];
    final agent = sodium.crypto.box.keyPair();
    final signer = sodium.crypto.sign.keyPair();
    final agentPrivateKey = agent.secretKey.extractBytes();
    final signingPrivateKey = signer.secretKey.extractBytes();
    final entries = <ScriptExecutionPackageEntryInput>[];
    final entryPlaintexts = <Uint8List>[];
    for (var index = 0; index < referenceIds.length; index++) {
      final isKey = index == 3;
      final plaintext = canonicalVaultJson({
        'schema': 'palladin.member-secret.v1',
        'entryType': isKey ? 'key' : 'credential',
        'memberLabel': 'Reference $index',
        'agentLabel': 'Reference $index',
        'description': null,
        'icon': null,
        'color': null,
        'discoverable': true,
        'content': isKey
            ? {'value': '5432', 'notes': null, 'customFields': const []}
            : {
                'username': 'fixture_user',
                'password': 'fixture_password',
                'url': 'postgresql://fixture.invalid',
                'urlDomain': 'fixture.invalid',
                'totp': null,
                'notes': null,
                'customFields': const [],
              },
        'agentFieldAccess': {fieldIds[index]: 'onGrantValue'},
      });
      entryPlaintexts.add(plaintext);
      entries.add(
        ScriptExecutionPackageEntryInput(
          entryId: referenceIds[index],
          entryRevision: '${index + 2}',
          encodedMemberSecret: plaintext,
        ),
      );
    }

    Uint8List? fingerprint;
    Uint8List? aad;
    Uint8List? parentInput;
    Uint8List? parentHash;
    Uint8List? packageKey;
    Uint8List? suitePayload;
    Uint8List? opened;
    try {
      final package =
          await ScriptExecutionPackageService(
            sodiumLoader: () async => sodium,
          ).seal(
            grantId: grantId,
            packageRevision: 1,
            agentId: agentId,
            agentAccessEpoch: 3,
            agentPublicKey: agent.publicKey,
            recipientAgentKeyVersion: 4,
            vaultSigningKeyVersion: 5,
            vaultSigningPrivateKey: signingPrivateKey,
            scriptEntry: const {
              'organizationId': organizationId,
              'vaultId': vaultId,
              'id': scriptId,
              'currentRevision': '7',
            },
            scriptPayload: {
              'script': 'printf "%s" "\$DB_USER"',
              'interpreter': 'bash',
              'refs': [
                for (var index = 0; index < referenceIds.length; index++)
                  ScriptRef(
                    env: environmentNames[index],
                    vaultId: vaultId,
                    entryId: referenceIds[index],
                    field: fieldIds[index],
                  ).toJson(),
              ],
              'execution': const ScriptExecutionMetadata(
                description: 'Fetch database users',
                parameters: [
                  ScriptParameterDefinition(
                    name: 'team_id',
                    description: 'Team identifier',
                    type: ScriptParameterType.string,
                    required: true,
                  ),
                ],
                returnResultToAgent: true,
              ).toJson(),
            },
            referencedEntries: entries,
          );

      expect(package['grantId'], grantId);
      expect(package['packageRevision'], '1');
      expect(package['vaultSigningKeyVersion'], 5);
      expect(package['scopes'], hasLength(5));
      final unsignedPackage = <String, Object?>{
        for (final item in package.entries)
          if (item.key != 'producerSignature') item.key: item.value,
      };
      expect(
        await VaultProtocolSignatureService(
          sodiumLoader: () async => sodium,
        ).verify(
          domainPrefix: 'PLDNV2SIG:SCRIPT-EXECUTION-PACKAGE:',
          unsignedObject: unsignedPackage,
          signature: package['producerSignature'] as String,
          publicKey: signer.publicKey,
        ),
        isTrue,
      );
      final transport = <String, Object?>{
        for (final item in package.entries)
          if (item.key != 'encodedPackageCiphertext' &&
              item.key != 'producerSignature')
            item.key: item.value,
      };
      aad = canonicalVaultJson(transport);
      parentInput = Uint8List.fromList([
        ...ascii.encode('PLDNSCRIPTAAD1'),
        ...aad,
      ]);
      parentHash = Uint8List.fromList(sha256.convert(parentInput).bytes);
      fingerprint = vaultPublicKeyFingerprint(
        VaultPublicKeyKind.agentX25519,
        agent.publicKey,
      );
      final container =
          jsonDecode(
                utf8.decode(
                  VaultProtocolBytes.base64UrlDecode(
                    package['encodedPackageCiphertext'] as String,
                  ),
                ),
              )
              as Map<String, dynamic>;
      final context = WrapperContext(
        purpose: WrapperPurpose.scriptExecutionDek,
        scope: EnvelopeScope(
          organizationId: EnvelopeId.parse(organizationId),
          vaultId: EnvelopeId.parse(vaultId),
          entryId: EnvelopeId.parse(scriptId),
          grantOrRequestId: EnvelopeId.parse(grantId),
          agentId: EnvelopeId.parse(agentId),
        ),
        resourceRevision: 1,
        wrappedKeyVersion: 1,
        recipientKeyVersion: 4,
        recipientFingerprint: fingerprint,
        parentDescriptorHash: parentHash,
      );
      packageKey =
          await X25519SealedBoxKeyWrapper(
            sodiumLoader: () async => sodium,
          ).open(
            wrapped: VaultProtocolBytes.base64UrlDecode(
              container['encodedSealedPackageDek'] as String,
            ),
            context: context,
            recipientSecretKey: agentPrivateKey,
          );
      suitePayload = VaultProtocolBytes.base64UrlDecode(
        container['encodedSuitePayload'] as String,
      );
      final key = SecureKey.fromList(sodium, packageKey);
      try {
        opened = sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
          cipherText: Uint8List.sublistView(suitePayload, 24),
          nonce: Uint8List.sublistView(suitePayload, 0, 24),
          key: key,
          additionalData: aad,
        );
      } finally {
        key.dispose();
      }
      final payload = jsonDecode(utf8.decode(opened)) as Map<String, dynamic>;
      final manifest = payload['manifest'] as Map<String, dynamic>;
      expect(manifest['references'], hasLength(4));
      expect(manifest['returnResultToAgent'], isTrue);
      expect(manifest['parameters'], [
        {
          'description': 'Team identifier',
          'name': 'team_id',
          'required': true,
          'type': 'string',
        },
      ]);
      final payloadEntries = (payload['entries'] as List).cast<Map>();
      expect(payloadEntries, hasLength(4));
      for (var index = 0; index < payloadEntries.length; index++) {
        expect(payloadEntries[index].keys, {
          'entryId',
          'entryRevision',
          'encodedGrantPayload',
        });
        final projection =
            jsonDecode(
                  utf8.decode(
                    VaultProtocolBytes.base64UrlDecode(
                      payloadEntries[index]['encodedGrantPayload'] as String,
                    ),
                  ),
                )
                as Map<String, dynamic>;
        expect(projection['schema'], 'palladin.grant-payload.v1');
        final fields = (projection['fields'] as List).cast<Map>();
        expect(fields, hasLength(1));
        expect(fields.single['id'], fieldIds[index]);
      }
      expect((payload['binding'] as Map)['authorization'], {
        'grantId': grantId,
        'source': 'scriptExecution',
      });
    } finally {
      for (final value in entryPlaintexts) {
        value.fillRange(0, value.length, 0);
      }
      for (final value in [
        fingerprint,
        aad,
        parentInput,
        parentHash,
        packageKey,
        suitePayload,
        opened,
      ]) {
        value?.fillRange(0, value.length, 0);
      }
      agentPrivateKey.fillRange(0, agentPrivateKey.length, 0);
      signingPrivateKey.fillRange(0, signingPrivateKey.length, 0);
      agent.dispose();
      signer.dispose();
    }
  });
}
