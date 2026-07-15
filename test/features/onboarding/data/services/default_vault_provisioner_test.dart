import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/onboarding/data/datasources/onboarding_remote_datasource.dart';
import 'package:mobile_palladin/features/onboarding/data/models/default_vault_request.dart';
import 'package:mobile_palladin/features/onboarding/data/services/default_vault_provisioner.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';

class _MockRemoteDatasource extends Mock
    implements OnboardingRemoteDatasource {}

class _MockVaultCryptoService extends Mock implements VaultCryptoService {}

class _MockTokenStorage extends Mock implements SecureTokenStorage {}

void main() {
  late _MockRemoteDatasource remoteDatasource;
  late _MockVaultCryptoService vaultCryptoService;
  late _MockTokenStorage tokenStorage;
  late DefaultVaultProvisioner provisioner;

  final privateKey = Uint8List.fromList(List.filled(32, 7));

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(
      const DefaultVaultRequest(name: 'Personal', wrappedVK: 'wrapped'),
    );
  });

  setUp(() {
    remoteDatasource = _MockRemoteDatasource();
    vaultCryptoService = _MockVaultCryptoService();
    tokenStorage = _MockTokenStorage();
    provisioner = DefaultVaultProvisioner(
      remoteDatasource: remoteDatasource,
      vaultCryptoService: vaultCryptoService,
      tokenStorage: tokenStorage,
    );
  });

  test(
    'creates and records the default vault when provisioning is pending',
    () async {
      when(
        () => tokenStorage.defaultVaultProvisioned,
      ).thenAnswer((_) async => false);
      when(
        () => vaultCryptoService.generateWrappedVK(privateKey),
      ).thenAnswer((_) async => 'wrapped');
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

      final request =
          verify(
                () => remoteDatasource.createDefaultVault(captureAny()),
              ).captured.single
              as DefaultVaultRequest;
      expect(request.name, 'Personal');
      expect(request.wrappedVK, 'wrapped');
      verify(() => tokenStorage.setDefaultVaultProvisioned(true)).called(1);
    },
  );

  test(
    'skips crypto and network when the vault is already provisioned',
    () async {
      when(
        () => tokenStorage.defaultVaultProvisioned,
      ).thenAnswer((_) async => true);

      await provisioner.ensureFromPrivateKey(
        privateKey: privateKey,
        name: 'Personal',
      );

      verifyNever(() => vaultCryptoService.generateWrappedVK(any()));
      verifyNever(() => remoteDatasource.createDefaultVault(any()));
    },
  );

  test('treats an existing default vault response as success', () async {
    when(
      () => tokenStorage.defaultVaultProvisioned,
    ).thenAnswer((_) async => null);
    when(
      () => vaultCryptoService.generateWrappedVK(privateKey),
    ).thenAnswer((_) async => 'wrapped');
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

  test('keeps provisioning pending when the backend request fails', () async {
    when(
      () => tokenStorage.defaultVaultProvisioned,
    ).thenAnswer((_) async => false);
    when(
      () => vaultCryptoService.generateWrappedVK(privateKey),
    ).thenAnswer((_) async => 'wrapped');
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
    verifyNever(() => tokenStorage.setDefaultVaultProvisioned(true));
  });
}
