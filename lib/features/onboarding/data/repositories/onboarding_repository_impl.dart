import 'dart:io';
import 'package:dio/dio.dart';

import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/mnemonic.dart' as mnemonic;
import '../../domain/repositories/onboarding_repository.dart';
import '../datasources/onboarding_remote_datasource.dart';
import '../models/account_setup_request.dart';
import '../services/default_vault_provisioner.dart';
import '../services/onboarding_crypto_service.dart';
import '../../../unlock/data/services/identity_kdf_service.dart';

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
    required this.defaultVaultProvisioner,
    required this.tokenStorage,
  });

  final OnboardingRemoteDatasource remoteDatasource;
  final OnboardingCryptoService cryptoService;
  final DefaultVaultProvisioner defaultVaultProvisioner;
  final SecureTokenStorage tokenStorage;

  @override
  Future<List<String>> generateRecoveryMnemonic() async {
    return mnemonic.generateRecoveryMnemonic();
  }

  @override
  Future<OnboardingUnlockKeys> completeSetup({
    required String masterPassword,
    required List<String> recoveryMnemonic,
    required String defaultVaultName,
  }) async {
    AppLogger.d('Onboarding', 'Building setup payload');
    final accountId = await tokenStorage.userId;
    if (accountId == null || accountId.isEmpty) {
      throw const OnboardingServerException(
        OnboardingServerErrorKind.invalidResponse,
      );
    }
    final result = await cryptoService.buildSetupPayload(
      masterPassword: masterPassword,
      recoveryMnemonic: recoveryMnemonic,
      accountId: accountId,
    );
    final payload = result.payload;

    try {
      final request = AccountSetupRequest(
        securityVersion: IdentityKdfProfile.securityVersion,
        kdfProfileId: IdentityKdfProfile.id,
        newAuthCredential: payload.authCredential,
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
          // success, not an error). These freshly derived keys are NOT
          // the account's real keys, so they must not seed a session —
          // the catch below zeroes them before this rethrows.
          AppLogger.w('Onboarding', 'Account already onboarded (409)');
          await tokenStorage.setOnboarded(true);
          throw OnboardingAlreadyCompletedException();
        }
        AppLogger.e('Onboarding', 'Setup failed', error: e, stackTrace: s);
        throw OnboardingServerException(_classifyError(e));
      }

      // Auto-create the default vault through the same challenge-bound,
      // canonical encrypted contract as normal Vault creation. A 409 means
      // the default Vault already exists; other transient failures remain
      // retryable and do not discard the newly established local session.
      try {
        await defaultVaultProvisioner.ensureFromPrivateKey(
          privateKey: result.privateKey,
          name: defaultVaultName,
        );
      } catch (error, stackTrace) {
        AppLogger.e(
          'Onboarding',
          'Default vault creation failed (non-blocking)',
          error: error,
          stackTrace: stackTrace,
        );
      }

      // NOTE: the master key is intentionally NOT persisted here. Biometric
      // unlock is enrolled — into the enclave-bound, biometric-gated store —
      // on the user's first password unlock (see UnlockCubit). Writing the
      // raw MK to secure storage at onboarding would violate that boundary.

      return OnboardingUnlockKeys(
        masterKey: result.masterKey,
        privateKey: result.privateKey,
      );
    } catch (_) {
      // On any failure the caller never receives the keys, so zero the
      // retained copies before they are dropped.
      result.masterKey.fillRange(0, result.masterKey.length, 0);
      result.privateKey.fillRange(0, result.privateKey.length, 0);
      rethrow;
    } finally {
      payload.authCredential.fillRange(0, payload.authCredential.length, 0);
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
