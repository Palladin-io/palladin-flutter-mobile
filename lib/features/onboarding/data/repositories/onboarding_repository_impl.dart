import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/mnemonic.dart' as mnemonic;
import '../../domain/repositories/onboarding_repository.dart';
import '../datasources/onboarding_remote_datasource.dart';
import '../models/account_setup_request.dart';
import '../services/onboarding_crypto_service.dart';

/// Concrete implementation of [OnboardingRepository].
///
/// Orchestrates mnemonic generation, key derivation / encryption via
/// [OnboardingCryptoService], and submission of the resulting payload
/// to the backend.
class OnboardingRepositoryImpl implements OnboardingRepository {
  OnboardingRepositoryImpl({
    required this.remoteDatasource,
    required this.cryptoService,
    required this.tokenStorage,
  });

  final OnboardingRemoteDatasource remoteDatasource;
  final OnboardingCryptoService cryptoService;
  final SecureTokenStorage tokenStorage;

  @override
  Future<List<String>> generateRecoveryMnemonic() async {
    return mnemonic.generateRecoveryMnemonic();
  }

  @override
  Future<void> completeSetup({
    required String masterPassword,
    required List<String> recoveryMnemonic,
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
        AppLogger.w('Onboarding', 'Account already onboarded (409)');
        throw OnboardingAlreadyCompletedException();
      }
      AppLogger.e('Onboarding', 'Setup failed', error: e, stackTrace: s);
      throw OnboardingServerException(_classifyError(e));
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
