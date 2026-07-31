import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/onboarding/data/datasources/onboarding_remote_datasource.dart';
import 'package:mobile_palladin/features/onboarding/data/services/default_vault_provisioner.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/vault/data/models/vault_v2_contracts.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';

class _MockRemoteDatasource extends Mock
    implements OnboardingRemoteDatasource {}

class _MockVaultCryptoService extends Mock implements VaultCryptoService {}

class _MockTokenStorage extends Mock implements SecureTokenStorage {}

class _MockAccountRemoteDatasource extends Mock
    implements AccountRemoteDatasource {}

void main() {
  const organizationId = '11111111-1111-4111-8111-111111111111';
  const userId = '22222222-2222-4222-8222-222222222222';
  const vaultId = '33333333-3333-4333-8333-333333333333';
  late _MockRemoteDatasource remoteDatasource;
  late _MockVaultCryptoService vaultCryptoService;
  late _MockTokenStorage tokenStorage;
  late _MockAccountRemoteDatasource accountRemoteDatasource;
  late DefaultVaultProvisioner provisioner;

  final privateKey = Uint8List.fromList(List.filled(32, 7));

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(GrantMode.granular);
  });

  setUp(() {
    remoteDatasource = _MockRemoteDatasource();
    vaultCryptoService = _MockVaultCryptoService();
    tokenStorage = _MockTokenStorage();
    accountRemoteDatasource = _MockAccountRemoteDatasource();
    provisioner = DefaultVaultProvisioner(
      remoteDatasource: remoteDatasource,
      vaultCryptoService: vaultCryptoService,
      tokenStorage: tokenStorage,
      accountRemoteDatasource: accountRemoteDatasource,
    );
  });

  void arrangeContext({CreatedVaultBundle? bundle}) {
    final payload = base64Url.encode(
      utf8.encode(jsonEncode({'org_id': organizationId})),
    );
    when(
      () => tokenStorage.accessToken,
    ).thenAnswer((_) async => 'header.$payload.signature');
    when(() => accountRemoteDatasource.getAccount()).thenAnswer(
      (_) async => const AccountResponse(userId: userId, memberKeyVersion: 7),
    );
    when(
      () => remoteDatasource.issueVaultCreationChallenge(),
    ).thenAnswer((_) async => {'vaultId': vaultId});
    when(
      () => vaultCryptoService.createVaultBundle(
        organizationId: any(named: 'organizationId'),
        memberId: any(named: 'memberId'),
        memberKeyVersion: any(named: 'memberKeyVersion'),
        vaultId: any(named: 'vaultId'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
        name: any(named: 'name'),
        grantMode: any(named: 'grantMode'),
      ),
    ).thenAnswer((_) async => bundle ?? _bundle(vaultId));
  }

  test(
    'submits the complete canonical challenge-bound Vault request',
    () async {
      when(
        () => tokenStorage.defaultVaultProvisioned,
      ).thenAnswer((_) async => false);
      arrangeContext();
      when(() => remoteDatasource.createDefaultVault(any())).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/account/default-vault'),
          statusCode: 201,
        ),
      );
      when(
        () => tokenStorage.setDefaultVaultProvisioned(true),
      ).thenAnswer((_) async {});

      await provisioner.ensureFromPrivateKey(
        privateKey: privateKey,
        name: 'Personal',
      );

      verify(
        () => vaultCryptoService.createVaultBundle(
          organizationId: organizationId,
          memberId: userId,
          memberKeyVersion: 7,
          vaultId: vaultId,
          memberPrivateKey: privateKey,
          name: 'Personal',
          grantMode: GrantMode.granular,
        ),
      ).called(1);
      final request =
          verify(
                () => remoteDatasource.createDefaultVault(captureAny()),
              ).captured.single
              as Map<String, dynamic>;
      expect(request['vaultId'], vaultId);
      expect(request['memberVaultMetadata'], isA<Map>());
      expect(request['currentKeyEpoch'], isA<Map>());
      expect(request['creatorVaultKey'], isA<Map>());
      expect(request['discoveryKey'], isA<Map>());
      expect(request['vaultPrivateKeys'], isA<List>());
      expect(request['vaultAgentMessagePublicKey'], isA<Map>());
      expect(request['vaultManifestSigningPublicKey'], isA<Map>());
      expect(request, isNot(contains('name')));
      expect(request, isNot(contains('wrappedVK')));
      verify(() => tokenStorage.setDefaultVaultProvisioned(true)).called(1);
    },
  );

  test('zeroes generated Vault keys after submission', () async {
    when(
      () => tokenStorage.defaultVaultProvisioned,
    ).thenAnswer((_) async => false);
    final bundle = _bundle(vaultId);
    arrangeContext(bundle: bundle);
    when(() => remoteDatasource.createDefaultVault(any())).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/api/account/default-vault'),
        statusCode: 201,
      ),
    );
    when(
      () => tokenStorage.setDefaultVaultProvisioned(true),
    ).thenAnswer((_) async {});

    await provisioner.ensureFromPrivateKey(
      privateKey: privateKey,
      name: 'Personal',
    );

    expect(bundle.vaultKey, everyElement(0));
    expect(bundle.vaultDiscoveryKey, everyElement(0));
  });

  test('skips context, crypto and network when already provisioned', () async {
    when(
      () => tokenStorage.defaultVaultProvisioned,
    ).thenAnswer((_) async => true);

    await provisioner.ensureFromPrivateKey(
      privateKey: privateKey,
      name: 'Personal',
    );

    verifyNever(() => accountRemoteDatasource.getAccount());
    verifyNever(() => remoteDatasource.issueVaultCreationChallenge());
    verifyNever(() => remoteDatasource.createDefaultVault(any()));
  });

  test('treats an existing default vault response as success', () async {
    when(
      () => tokenStorage.defaultVaultProvisioned,
    ).thenAnswer((_) async => null);
    arrangeContext();
    when(() => remoteDatasource.createDefaultVault(any())).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/account/default-vault'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/account/default-vault'),
          statusCode: 409,
        ),
      ),
    );
    when(
      () => tokenStorage.setDefaultVaultProvisioned(true),
    ).thenAnswer((_) async {});

    await provisioner.ensureFromPrivateKey(
      privateKey: privateKey,
      name: 'Personal',
    );

    verify(() => tokenStorage.setDefaultVaultProvisioned(true)).called(1);
  });

  test('keeps provisioning pending and zeroes keys on failure', () async {
    when(
      () => tokenStorage.defaultVaultProvisioned,
    ).thenAnswer((_) async => false);
    final bundle = _bundle(vaultId);
    arrangeContext(bundle: bundle);
    when(() => remoteDatasource.createDefaultVault(any())).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/account/default-vault'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/account/default-vault'),
          statusCode: 500,
        ),
      ),
    );

    await expectLater(
      provisioner.ensureFromPrivateKey(
        privateKey: privateKey,
        name: 'Personal',
      ),
      throwsA(isA<DioException>()),
    );
    expect(bundle.vaultKey, everyElement(0));
    expect(bundle.vaultDiscoveryKey, everyElement(0));
    verifyNever(() => tokenStorage.setDefaultVaultProvisioned(true));
  });
}

CreatedVaultBundle _bundle(String vaultId) {
  const scope = <String, Object?>{
    'organizationId': '11111111-1111-4111-8111-111111111111',
    'vaultId': '33333333-3333-4333-8333-333333333333',
    'entryId': null,
    'grantOrRequestId': null,
    'agentId': null,
    'memberId': null,
  };
  const envelope = VaultOpaqueEnvelopeModel(
    descriptor: {
      'protocolVersion': 2,
      'cryptoSuiteId': 'palladin-vault-xchacha-v1',
      'purpose': 1,
      'scope': scope,
      'resourceRevision': '1',
      'keyVersion': 1,
      'memberKeyGeneration': 1,
      'binding': <String, Object?>{},
    },
    encodedSuitePayload: 'ciphertext',
  );
  return CreatedVaultBundle(
    request: CreateVaultV2Request(
      vaultId: vaultId,
      memberVaultMetadata: envelope,
      currentKeyEpoch: const VaultKeyEpochModel(
        vaultKeyVersion: 1,
        vdkVersion: 1,
        agentMessageKeyVersion: 1,
        manifestSigningKeyVersion: 1,
      ),
      creatorVaultKey: const X25519WrappedKeyModel(
        descriptor: X25519WrapperDescriptorModel(
          wrapperSuiteId: 'palladin-x25519-sealed-box-v1',
          purpose: 1,
          scope: scope,
          resourceRevision: '1',
          wrappedKeyVersion: 1,
          memberKeyGeneration: 1,
          recipientKeyKind: 5,
          recipientKeyVersion: 7,
          recipientFingerprint: 'fingerprint',
        ),
        encodedSealedKeyPackage: 'sealed',
      ),
      discoveryKey: envelope,
      vaultPrivateKeys: const [envelope, envelope],
      vaultAgentMessagePublicKey: const VaultPublicKeyContractModel(
        schemeId: 'palladin-x25519-v1',
        keyKind: VaultPublicKeyKind.agentMessageX25519,
        keyVersion: 1,
        encodedPublicKey: 'public',
        fingerprint: 'fingerprint',
      ),
      vaultManifestSigningPublicKey: const VaultPublicKeyContractModel(
        schemeId: 'palladin-ed25519-v1',
        keyKind: VaultPublicKeyKind.manifestSigningEd25519,
        keyVersion: 1,
        encodedPublicKey: 'public',
        fingerprint: 'fingerprint',
      ),
    ),
    vaultKey: Uint8List.fromList(List.filled(32, 4)),
    vaultDiscoveryKey: Uint8List.fromList(List.filled(32, 5)),
    metadata: const MemberVaultMetadata(
      name: 'Personal',
      description: null,
      icon: null,
      color: null,
      grantMode: 'granular',
    ),
    memberFingerprint: 'fingerprint',
  );
}
