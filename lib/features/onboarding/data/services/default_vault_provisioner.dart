import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../vault/data/services/vault_crypto_service.dart';
import '../datasources/onboarding_remote_datasource.dart';
import '../models/default_vault_request.dart';

/// Idempotently provisions the encrypted default vault on the client.
///
/// The plaintext VK is generated and wrapped by [VaultCryptoService]. Only
/// the wrapped value is sent to the backend. A persisted boolean tracks a
/// pending retry, but no key material is ever written to storage.
class DefaultVaultProvisioner {
  DefaultVaultProvisioner({
    required this.remoteDatasource,
    required this.vaultCryptoService,
    required this.tokenStorage,
  });

  final OnboardingRemoteDatasource remoteDatasource;
  final VaultCryptoService vaultCryptoService;
  final SecureTokenStorage tokenStorage;

  /// Whether registration explicitly left a default vault to be created.
  Future<bool> get isRequired async =>
      await tokenStorage.defaultVaultProvisioned == false;

  Future<void> ensureFromPrivateKey({
    required Uint8List privateKey,
    required String name,
  }) async {
    if (await tokenStorage.defaultVaultProvisioned == true) return;

    final wrappedVK = await vaultCryptoService.generateWrappedVK(privateKey);
    await _submit(name: name, wrappedVK: wrappedVK);
  }

  Future<void> ensureFromPublicKey({
    required Uint8List publicKey,
    required String name,
  }) async {
    if (await tokenStorage.defaultVaultProvisioned == true) return;

    final wrappedVK = await vaultCryptoService.generateWrappedVKFromPublicKey(
      publicKey,
    );
    await _submit(name: name, wrappedVK: wrappedVK);
  }

  Future<void> _submit({
    required String name,
    required String wrappedVK,
  }) async {
    try {
      AppLogger.d('Onboarding', 'POST /api/account/default-vault');
      await remoteDatasource.createDefaultVault(
        DefaultVaultRequest(name: name, wrappedVK: wrappedVK),
      );
      AppLogger.i('Onboarding', 'Default vault created');
    } on DioException catch (error) {
      if (error.response?.statusCode != 409) rethrow;
      AppLogger.i(
        'Onboarding',
        'Default vault already exists (409) - skipping',
      );
    }

    await tokenStorage.setDefaultVaultProvisioned(true);
  }
}
