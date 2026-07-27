import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../unlock/data/datasources/account_remote_datasource.dart';
import '../../../unlock/data/services/unlock_crypto_service.dart';
import '../../../unlock/data/services/identity_kdf_service.dart';
import '../../data/datasources/password_auth_remote_datasource.dart';
import '../../data/models/login_response.dart';
import '../../data/models/password_session_model.dart';
import '../../domain/auth_provider_id.dart';
import '../../domain/password_auth_exceptions.dart';
import 'login_state.dart';

export 'login_state.dart';

/// Drives the email + master-password login (CVT-272) and the in-flow
/// TOTP challenge (CVT-275).
///
/// Flow:
///   1. `POST /api/auth/login/salt` → the account's auth salt.
///   2. Derive `authHash = Argon2id(password, authSalt)`.
///   3. `POST /api/auth/login` → a full session, or a TOTP challenge.
///   4. (if TOTP) `POST /api/auth/login/totp` with the 6-digit / recovery
///      code → a full session.
///   5. `GET /api/account` → derive the master key from the **same**
///      password and the account's encryption salt, decrypt the private
///      key, and emit [LoginSuccess].
///
/// The password and email are held in private fields **in memory only**
/// across the TOTP hop so the master key can be derived after the
/// challenge. They are never persisted, logged, or placed in state.
class LoginCubit extends Cubit<LoginState> {
  static const _antiEnumerationAccountId =
      '00000000-0000-4000-8000-000000000000';

  LoginCubit({
    required this.datasource,
    required this.identityKdfService,
    required this.accountDatasource,
    required this.unlockCryptoService,
    required this.tokenStorage,
  }) : super(const LoginInitial());

  final PasswordAuthRemoteDatasource datasource;
  final IdentityKdfService identityKdfService;
  final AccountRemoteDatasource accountDatasource;
  final UnlockCryptoService unlockCryptoService;
  final SecureTokenStorage tokenStorage;

  String? _challengeToken;
  Uint8List? _masterKey;
  String? _accountId;

  /// Runs the salt → authHash → login pipeline.
  Future<void> login({required String email, required String password}) async {
    if (email.isEmpty || password.isEmpty) return;
    AppLogger.d('Login', 'Password login requested');
    emit(const LoginLoading());

    try {
      final bootstrap = await datasource.fetchLoginKdf(
        email,
        profileId: IdentityKdfProfile.id,
      );
      if (bootstrap.profileId != IdentityKdfProfile.id ||
          bootstrap.securityVersion != IdentityKdfProfile.securityVersion ||
          bootstrap.memoryKiB != IdentityKdfProfile.memoryKiB ||
          bootstrap.iterations != IdentityKdfProfile.iterations ||
          bootstrap.parallelism != IdentityKdfProfile.parallelism) {
        throw const UnsupportedIdentityKdfException('unsupported-kdf-profile');
      }
      // Unknown accounts receive a pseudo-bootstrap without an account ID.
      // Derive against a syntactically valid, fixed UUID and still call login
      // so account existence is not exposed through behavior or timing.
      final derivationAccountId =
          bootstrap.accountId ?? _antiEnumerationAccountId;
      final salt = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(bootstrap.kdfSalt)),
      );
      final IdentityKdfOutputs outputs;
      try {
        outputs = await identityKdfService.derive(
          password: password,
          accountId: derivationAccountId,
          kdfSalt: salt,
        );
      } finally {
        salt.fillRange(0, salt.length, 0);
      }
      _masterKey?.fillRange(0, _masterKey!.length, 0);
      _masterKey = outputs.masterKey;
      _accountId = bootstrap.accountId;
      final authCredential = base64Url
          .encode(outputs.authCredential)
          .replaceAll('=', '');
      outputs.authCredential.fillRange(0, outputs.authCredential.length, 0);
      final response = await datasource.login(
        email: email,
        authCredential: authCredential,
      );

      switch (response) {
        case LoginSession(:final session):
          await _establishSession(session);
        case LoginTotpRequired(:final challengeToken):
          AppLogger.i('Login', 'TOTP challenge required');
          _challengeToken = challengeToken;
          emit(const LoginTotpChallenge());
      }
    } catch (e, s) {
      AppLogger.w('Login', 'Login failed: ${e.runtimeType}');
      _clearSecrets();
      emit(LoginFailure(_normalize(e, s)));
    }
  }

  /// Submits the TOTP (or recovery) code for the pending challenge.
  Future<void> submitTotp(String code) async {
    final challengeToken = _challengeToken;
    if (challengeToken == null || code.isEmpty) return;
    AppLogger.d('Login', 'Submitting TOTP challenge');
    emit(const LoginTotpVerifying());

    try {
      final session = await datasource.loginTotp(
        challengeToken: challengeToken,
        code: code,
      );
      await _establishSession(session);
    } on TotpInvalidException {
      AppLogger.w('Login', 'TOTP code rejected');
      emit(const LoginTotpChallenge(error: TotpInvalidException()));
    } catch (e, s) {
      AppLogger.w('Login', 'TOTP verification failed: ${e.runtimeType}');
      _clearSecrets();
      emit(LoginFailure(_normalize(e, s)));
    }
  }

  /// Persists the session, derives the master key from the held password,
  /// and emits [LoginSuccess].
  Future<void> _establishSession(PasswordSessionModel session) async {
    await tokenStorage.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      userId: session.userId,
      isOnboarded: session.isOnboarded,
    );
    await tokenStorage.setAuthProvider(AuthProviderId.password);

    final account = await accountDatasource.getAccount();
    final masterKey = _masterKey;
    if (masterKey == null || account.userId != _accountId) {
      throw const UnsupportedIdentityKdfException('account-context-mismatch');
    }
    final result = await unlockCryptoService.decryptWithMasterKey(
      masterKey: masterKey,
      encryptedPrivateKeyBase64: account.encryptedPrivateKey,
    );
    _clearSecrets();
    AppLogger.i('Login', 'Login succeeded, master key derived');
    emit(
      LoginSuccess(masterKey: result.masterKey, privateKey: result.privateKey),
    );
  }

  /// Drops the in-memory password / challenge token. Strings can't be
  /// zeroed, but dropping every reference lets them be collected.
  void _clearSecrets() {
    _challengeToken = null;
    _accountId = null;
    _masterKey?.fillRange(0, _masterKey!.length, 0);
    _masterKey = null;
  }

  @override
  Future<void> close() {
    _clearSecrets();
    return super.close();
  }

  /// Reduces a raw error to the typed exception the UI understands.
  Object _normalize(Object error, StackTrace stack) {
    if (error is InvalidCredentialsException ||
        error is LoginRateLimitedException ||
        error is TotpInvalidException ||
        error is PasswordAuthServerException) {
      return error;
    }
    // Master-key derivation or an unexpected failure — surface as a
    // generic server error the page can localize.
    AppLogger.e(
      'Login',
      'Unexpected login error',
      error: error,
      stackTrace: stack,
    );
    return const PasswordAuthServerException(
      PasswordAuthServerErrorKind.connectionFailed,
    );
  }
}
