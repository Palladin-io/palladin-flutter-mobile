import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../onboarding/domain/mnemonic.dart' as mnemonic;
import '../../data/datasources/password_auth_remote_datasource.dart';
import '../../data/models/register_request.dart';
import '../../data/services/password_auth_crypto_service.dart';
import 'register_state.dart';

export 'register_state.dart';

/// Drives the registration wizard (CVT-271).
///
/// Mirrors the shape of `OnboardingCubit` but for the email + master
/// password flow: it collects credentials, generates and confirms the
/// recovery mnemonic, then runs the zero-knowledge crypto pipeline and
/// submits `POST /api/auth/register`. On success it persists the returned
/// (unverified) session tokens and surfaces the freshly derived keys so
/// the page can seed an unlocked `AuthBloc` session — the router then
/// forwards the user to the email-verification gate.
class RegisterCubit extends Cubit<RegisterState> {
  RegisterCubit({
    required this.datasource,
    required this.cryptoService,
    required this.tokenStorage,
  }) : super(const RegisterState());

  final PasswordAuthRemoteDatasource datasource;
  final PasswordAuthCryptoService cryptoService;
  final SecureTokenStorage tokenStorage;

  /// Records the chosen email + master password and generates the recovery
  /// mnemonic, advancing to the backup step.
  Future<void> submitCredentials({
    required String email,
    required String password,
  }) async {
    AppLogger.d('Register', 'Credentials submitted, generating mnemonic');
    final phrase = mnemonic.generateRecoveryMnemonic();
    emit(state.copyWith(
      step: RegisterStep.recoveryKeyBackup,
      email: email,
      password: password,
      mnemonic: phrase,
      clearError: true,
    ));
  }

  /// Advances from the backup screen to the confirmation screen.
  void acknowledgeRecoveryBackup() {
    emit(state.copyWith(
      step: RegisterStep.recoveryKeyConfirm,
      clearError: true,
    ));
  }

  /// Runs the crypto pipeline and submits the registration.
  ///
  /// [preferredLanguage] is the current locale (`"pl"`/`"en"`) so the
  /// backend localizes the verification email.
  Future<void> completeRegistration({
    required String preferredLanguage,
  }) async {
    if (state.email.isEmpty || state.password.isEmpty || state.mnemonic.isEmpty) {
      AppLogger.w('Register', 'Cannot complete — missing credentials/mnemonic');
      return;
    }

    emit(state.copyWith(step: RegisterStep.submitting, clearError: true));

    final material = await cryptoService.buildRegistrationMaterial(
      password: state.password,
      recoveryMnemonic: state.mnemonic,
    );

    try {
      final request = RegisterRequest(
        email: state.email,
        displayName: _displayNameFrom(state.email),
        preferredLanguage: preferredLanguage,
        authHash: material.authHash,
        authSalt: material.authSalt,
        salt: material.encSalt,
        recoverySalt: material.recoverySalt,
        publicKey: material.publicKey,
        encryptedPrivateKey: material.encryptedPrivateKey,
        encryptedPrivateKeyByRecovery: material.encryptedPrivateKeyByRecovery,
      );

      AppLogger.d('Register', 'POST /api/auth/register');
      final session = await datasource.register(request);
      await tokenStorage.saveTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        userId: session.userId,
        isOnboarded: session.isOnboarded,
      );

      if (state.step != RegisterStep.submitting) return;
      AppLogger.i('Register', 'Registration complete');
      emit(state.copyWith(
        step: RegisterStep.completed,
        unlockKeys: RegisterUnlockKeys(
          masterKey: material.masterKey,
          privateKey: material.privateKey,
        ),
      ));
    } catch (e, s) {
      // On any failure the caller never receives the keys — zero the
      // retained copies before they are dropped.
      material.masterKey.fillRange(0, material.masterKey.length, 0);
      material.privateKey.fillRange(0, material.privateKey.length, 0);
      if (state.step != RegisterStep.submitting) return;
      AppLogger.e('Register', 'Registration failed', error: e, stackTrace: s);
      emit(state.copyWith(step: RegisterStep.recoveryKeyConfirm, error: e));
    }
  }

  /// Drops the cubit's reference to the freshly derived keys after the page
  /// has handed them to `AuthBloc`. The buffers are intentionally NOT
  /// zeroed — the same references now live in `AuthAuthenticated`.
  void clearUnlockKeys() {
    if (state.unlockKeys == null) return;
    emit(state.copyWith(clearUnlockKeys: true));
  }

  /// Goes back one wizard step (system back-button / swipe on steps 2–3).
  void goBack() {
    switch (state.step) {
      case RegisterStep.recoveryKeyBackup:
        emit(state.copyWith(step: RegisterStep.credentials, clearError: true));
      case RegisterStep.recoveryKeyConfirm:
        emit(state.copyWith(
          step: RegisterStep.recoveryKeyBackup,
          clearError: true,
        ));
      case RegisterStep.credentials:
      case RegisterStep.submitting:
      case RegisterStep.completed:
        break;
    }
  }

  /// Derives a display name from the email local-part (before `@`). The
  /// backend requires a non-empty display name; the mobile register form
  /// collects only email + password, so this is the sensible default.
  String _displayNameFrom(String email) {
    final at = email.indexOf('@');
    final local = at > 0 ? email.substring(0, at) : email;
    return local.isEmpty ? email : local;
  }
}
