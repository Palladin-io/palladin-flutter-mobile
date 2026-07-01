import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../vault/data/services/vault_crypto_service.dart';
import '../../domain/mnemonic.dart' as mnemonic;
import '../../domain/repositories/onboarding_repository.dart';
import '../datasources/onboarding_remote_datasource.dart';
import '../models/account_setup_request.dart';
import '../models/default_vault_request.dart';
import '../services/onboarding_crypto_service.dart';

/// Concrete implementation of [OnboardingRepository].
///
/// Orchestrates mnemonic generation, key derivation / encryption via
/// [OnboardingCryptoService], and submission of the resulting payload
/// to the backend.
///
/// After the account setup call succeeds, auto-creates the user's
/// default vault via `POST /api/account/default-vault` (zero-knowledge:
/// the VK is wrapped with the user's public key from the setup payload).
class OnboardingRepositoryImpl implements OnboardingRepository {
  OnboardingRepositoryImpl({
    required this.remoteDatasource,
    required this.cryptoService,
    required this.vaultCryptoService,
    required this.tokenStorage,
  });

  final OnboardingRemoteDatasource remoteDatasource;
  final OnboardingCryptoService cryptoService;
  final VaultCryptoService vaultCryptoService;
  final SecureTokenStorage tokenStorage;

  @override
  Future<List<String>> generateRecoveryMnemonic() async {
    return mnemonic.generateRecoveryMnemonic();
  }

  @override
  Future<void> completeSetup({
    required String masterPassword,
    required List<String> recoveryMnemonic,
    required String defaultVaultName,
  }) async {
    AppLogger.d('Onboarding', 'Building setup payload');
    final payload = await cryptoService.buildSetupPayload(
      masterPassword: masterPassword,
      recoveryMnemonic: recoveryMnemonic,
    );

    final request = AccountSetupRequest(
      salt: payload.salt,
      recoverySalt: payload.recoverySalt,
      publicKey: payload.publicKey,
      encryptedPrivateKey: payload.encryptedPrivateKey,
      encryptedPrivateKeyByRecovery: payload.encryptedPrivateKeyByRecovery,
    );

    try {
      AppLogger.d('Onboarding', 'POST /api/account/setup');
      await remoteDatasource.setupAccount(request);
      await tokenStorage.setOnboarded(true);
      AppLogger.i('Onboarding', 'Account setup complete');
    } on DioException catch (e, s) {
      if (e.response?.statusCode == 409) {
        // The backend says this account is already onboarded — mark the
        // local flag so the router stops redirecting here, then surface
        // the "already onboarded" signal to the UI (which treats it as
        // success, not an error).
        AppLogger.w('Onboarding', 'Account already onboarded (409)');
        await tokenStorage.setOnboarded(true);
        throw OnboardingAlreadyCompletedException();
      }
      AppLogger.e('Onboarding', 'Setup failed', error: e, stackTrace: s);
      throw OnboardingServerException(_classifyError(e));
    }

    // Auto-create the default vault using the public key from the setup
    // payload — the private key has already been zeroed by this point, but
    // the public key is sufficient to seal the VK (crypto_box_seal).
    // Fire-and-forget: 409 means the default vault already exists (safe
    // to swallow); any other transient error is logged and suppressed so
    // it never blocks the user from proceeding to the app.
    await _createDefaultVaultOrIgnore(
      publicKey: payload.publicKey,
      name: defaultVaultName,
    );
  }

  /// Wraps a fresh VK for [publicKey] and submits it to
  /// `POST /api/account/default-vault`. 409 (already exists) and any
  /// transient error are swallowed — the caller must never surface them.
  Future<void> _createDefaultVaultOrIgnore({
    required Uint8List publicKey,
    required String name,
  }) async {
    try {
      AppLogger.d('Onboarding', 'Generating wrapped VK for default vault');
      final wrappedVK = await vaultCryptoService.generateWrappedVKFromPublicKey(
        publicKey,
      );
      AppLogger.d('Onboarding', 'POST /api/account/default-vault');
      await remoteDatasource.createDefaultVault(
        DefaultVaultRequest(name: name, wrappedVK: wrappedVK),
      );
      AppLogger.i('Onboarding', 'Default vault created');
    } on DioException catch (e, s) {
      if (e.response?.statusCode == 409) {
        // Default vault already exists — idempotent, nothing to do.
        AppLogger.i('Onboarding', 'Default vault already exists (409) — skipping');
        return;
      }
      AppLogger.e(
        'Onboarding',
        'Default vault creation failed (non-blocking)',
        error: e,
        stackTrace: s,
      );
    } catch (e, s) {
      AppLogger.e(
        'Onboarding',
        'Default vault creation failed unexpectedly (non-blocking)',
        error: e,
        stackTrace: s,
      );
    }
  }

  /// Maps a [DioException] to a typed [OnboardingServerErrorKind].
  OnboardingServerErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return OnboardingServerErrorKind.serverNotResponding;
    }

    if (e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return OnboardingServerErrorKind.cannotConnect;
    }

    if (e.type == DioExceptionType.badResponse) {
      return OnboardingServerErrorKind.invalidResponse;
    }

    return OnboardingServerErrorKind.connectionFailed;
  }
}
