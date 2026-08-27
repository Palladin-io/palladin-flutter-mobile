import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/approval/data/services/encrypted_reason_crypto_service.dart';
import 'package:mobile_palladin/features/approval/data/services/grant_history_reason_resolver.dart';
import 'package:mobile_palladin/features/approval/domain/entities/encrypted_reason.dart';
import 'package:mobile_palladin/features/grants/data/models/grant_model.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/vault/data/datasources/agent_discovery_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/agent_discovery_provisioning.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Keys extends Mock implements VaultRotationCryptoService {}

class _Discovery extends Mock implements AgentDiscoveryRemote {}

class _ReasonCrypto extends Mock implements EncryptedReasonCrypto {}

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  test('decrypts history reason locally and wipes temporary buffers', () async {
    final messagePrivateKey = Uint8List.fromList(
      List<int>.generate(32, (index) => index + 1),
    );
    const fingerprint = 'authenticated-message-key-fingerprint';

    final reason = EncryptedReason(
      descriptor: {
        'protocolVersion': 2,
        'purpose': 'encryptedReason',
        'scope': {
          'organizationId': 'org-1',
          'vaultId': 'v-1',
          'entryId': 'e-1',
          'grantOrRequestId': 'g-1',
          'agentId': 'a-1',
          'memberId': null,
        },
        'resourceRevision': '1',
        'keyVersion': 1,
        'memberKeyGeneration': 1,
        'binding': {
          'recipientKeyVersion': 1,
          'recipientKeyFingerprint': fingerprint,
          'requestedMethods': 1,
        },
      },
      encodedSuitePayload: 'payload',
      wrappedReasonDek: const {},
      agentSignature: 'signature',
    );
    final encryptedReason = <String, dynamic>{
      'descriptor': reason.descriptor,
      'encodedSuitePayload': reason.encodedSuitePayload,
      'wrappedReasonDek': reason.wrappedReasonDek,
      'agentSignature': reason.agentSignature,
    };
    registerFallbackValue(reason);
    final grant = GrantModel(
      id: 'g-1',
      vaultId: 'v-1',
      agentId: 'a-1',
      status: 'active',
      type: GrantScope.granular,
      createdAt: '2026-08-07T10:00:00Z',
      entryId: 'e-1',
      methods: 'get',
      encryptedReason: encryptedReason,
    );
    final vaults = _Vaults();
    final keys = _Keys();
    final discovery = _Discovery();
    final reasonCrypto = _ReasonCrypto();
    final vaultKey = Uint8List.fromList(List<int>.filled(32, 7));
    final reasonKey = Uint8List.fromList(List<int>.filled(32, 8));
    final plaintext = Uint8List.fromList(
      utf8.encode('{"reason":"Deploy release"}'),
    );
    final signingKey = Uint8List.fromList(List<int>.filled(32, 9));

    when(() => vaults.getEncryptedVault('v-1')).thenAnswer(
      (_) async => <String, dynamic>{
        'organizationId': 'org-1',
        'memberVaultKey': <String, dynamic>{'wrappedVaultKey': const {}},
        'vaultPrivateKeys': <Map<String, dynamic>>[
          {
            'descriptor': {
              'purpose': 'vaultAgentMessagePrivateKey',
              'keyVersion': 1,
            },
          },
        ],
      },
    );
    when(
      () => keys.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => vaultKey);
    when(
      () => keys.openCanonicalAgentMessagePrivateKey(
        any(),
        any(),
        expectedKeyVersion: 1,
      ),
    ).thenAnswer((_) async => messagePrivateKey);
    when(() => discovery.list('v-1')).thenAnswer(
      (_) async => [
        AgentDiscoveryProvisioning(
          agentId: 'a-1',
          recipientKeyVersion: 1,
          status: 'current',
          x25519PublicKey: base64Encode(List<int>.filled(32, 1)),
          ed25519PublicKey: base64Encode(signingKey),
        ),
      ],
    );
    when(
      () => reasonCrypto.verifyAndOpenKey(
        reason: any(named: 'reason'),
        signingPublicKey: any(named: 'signingPublicKey'),
        recipientPrivateKey: any(named: 'recipientPrivateKey'),
      ),
    ).thenAnswer((_) async => reasonKey);
    when(
      () => reasonCrypto.decrypt(
        reason: any(named: 'reason'),
        reasonKey: reasonKey,
      ),
    ).thenAnswer((_) async => plaintext);

    final result =
        await LocalGrantReasonResolver(
          vaults: vaults,
          keys: keys,
          discovery: discovery,
          reasonCrypto: reasonCrypto,
          messageKeyFingerprint: (_) async => fingerprint,
        ).resolve(
          grants: [grant],
          memberPrivateKey: Uint8List.fromList(List<int>.filled(32, 5)),
        );

    expect(result, {'g-1': 'Deploy release'});
    expect(vaultKey, everyElement(0));
    expect(messagePrivateKey, everyElement(0));
    expect(reasonKey, everyElement(0));
    expect(plaintext, everyElement(0));
  });
}
