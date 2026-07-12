import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../unlock/data/datasources/account_remote_datasource.dart';
import '../../../unlock/data/services/unlock_crypto_service.dart';
import '../../data/datasources/password_auth_remote_datasource.dart';
import '../../data/models/login_response.dart';
import '../../data/models/password_session_model.dart';
import '../../data/services/password_auth_crypto_service.dart';
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
  LoginCubit({
    required this.datasource,
    required this.cryptoService,
    required this.accountDatasource,
    required this.unlockCryptoService,
    required this.tokenStorage,
  }) : super(const LoginInitial());

  final PasswordAuthRemoteDatasource datasource;
  final PasswordAuthCryptoService cryptoService;
  final AccountRemoteDatasource accountDatasource;
  final UnlockCryptoService unlockCryptoService;
  final SecureTokenStorage tokenStorage;

  String? _password;
  String? _challengeToken;

  /// Runs the salt → authHash → login pipeline.
  Future<void> login({required String email, required String password}) async {
    if (email.isEmpty || password.isEmpty) return;
    AppLogger.d('Login', 'Password login requested');
    emit(const LoginLoading());
    _password = password;

    try {
      final authSalt = await datasource.fetchLoginSalt(email);
      final authHash = await cryptoService.deriveAuthHash(
        password: password,
        authSaltBase64: authSalt,
      );
      final response = await datasource.login(email: email, authHash: authHash);

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
    final result = await unlockCryptoService.deriveAndDecrypt(
      masterPassword: _password!,
      saltBase64: account.salt,
      encryptedPrivateKeyBase64: account.encryptedPrivateKey,
    );
    _clearSecrets();
    AppLogger.i('Login', 'Login succeeded, master key derived');
    emit(LoginSuccess(
      masterKey: result.masterKey,
      privateKey: result.privateKey,
    ));
  }

  /// Drops the in-memory password / challenge token. Strings can't be
  /// zeroed, but dropping every reference lets them be collected.
  void _clearSecrets() {
    _password = null;
    _challengeToken = null;
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
    AppLogger.e('Login', 'Unexpected login error', error: error, stackTrace: stack);
    return const PasswordAuthServerException(
      PasswordAuthServerErrorKind.connectionFailed,
    );
  }
}
