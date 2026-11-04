import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/account_secret_store.dart';
import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/storage/biometric_key_store.dart';
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

/// Drives the email + master-password login and the in-flow
/// TOTP challenge.
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
    required this.identityKdfService,
    required this.accountDatasource,
    required this.unlockCryptoService,
    required this.tokenStorage,
    required this.keyStore,
    required this.accountSecrets,
  }) : super(const LoginInitial());

  final PasswordAuthRemoteDatasource datasource;
  final IdentityKdfService identityKdfService;
  final AccountRemoteDatasource accountDatasource;
  final UnlockCryptoService unlockCryptoService;
  final SecureTokenStorage tokenStorage;
  final BiometricKeyStore keyStore;
  final AccountSecretStore accountSecrets;
  int? _biometricGeneration;

  /// Held in memory only while this device waits for the Secret Key.
  String? _pendingEmail;
  String? _pendingPassword;
  LoginKdfBootstrap? _pendingBootstrap;

  /// Secret Key obtained on this device in this attempt; persisted only after
  /// the server accepts the derived credential.
  Uint8List? _newAccountSecret;
  IdentityKdfVersion? _kdfVersion;

  String? _challengeToken;
  Uint8List? _masterKey;
  String? _accountId;

  /// Runs the salt → authHash → login pipeline.
  Future<void> login({required String email, required String password}) async {
    if (email.isEmpty || password.isEmpty || isClosed) return;
    _biometricGeneration = keyStore.generation;
    AppLogger.d('Login', 'Password login requested');
    emit(const LoginLoading());

    try {
      final bootstrap = await datasource.fetchLoginKdf(
        email,
        profileId: IdentityKdfProfileV2.id,
      );
      final version = _verifiedVersion(bootstrap);
      if (version == IdentityKdfVersion.accountSecretV2) {
        final stored = await accountSecrets.read(bootstrap.accountId);
        if (_isCanceled) {
          stored?.fillRange(0, stored.length, 0);
          return;
        }
        if (stored == null) {
          _pendingEmail = email;
          _pendingPassword = password;
          _pendingBootstrap = bootstrap;
          emit(
            LoginSecretKeyRequired(
              accountId: bootstrap.accountId,
              email: email,
            ),
          );
          return;
        }
        await _signIn(email, password, bootstrap, version, stored);
      } else {
        await _signIn(email, password, bootstrap, version, null);
      }
    } catch (e, s) {
      AppLogger.w('Login', 'Login failed: ${e.runtimeType}');
      _clearSecrets();
      if (!isClosed) emit(LoginFailure(_normalize(e, s)));
    }
  }

  /// Continues a version-2 sign-in with a Secret Key obtained from another
  /// device or the Emergency Kit. Takes ownership of [accountSecret].
  Future<void> continueWithSecretKey(Uint8List accountSecret) async {
    final email = _pendingEmail;
    final password = _pendingPassword;
    final bootstrap = _pendingBootstrap;
    if (email == null || password == null || bootstrap == null || isClosed) {
      accountSecret.fillRange(0, accountSecret.length, 0);
      return;
    }
    _biometricGeneration = keyStore.generation;
    emit(const LoginLoading());
    _newAccountSecret = accountSecret;
    try {
      await _signIn(
        email,
        password,
        bootstrap,
        IdentityKdfVersion.accountSecretV2,
        Uint8List.fromList(accountSecret),
      );
    } catch (e, s) {
      AppLogger.w('Login', 'Login failed: ${e.runtimeType}');
      _clearSecrets();
      if (!isClosed) emit(LoginFailure(_normalize(e, s)));
    }
  }

  /// Abandons a pending Secret Key request and returns to the form.
  void cancelSecretKeyRequest() {
    _clearSecrets();
    if (!isClosed) emit(const LoginInitial());
  }

  IdentityKdfVersion _verifiedVersion(LoginKdfBootstrap bootstrap) {
    final v1 =
        bootstrap.profileId == IdentityKdfProfile.id &&
        bootstrap.securityVersion == IdentityKdfProfile.securityVersion &&
        bootstrap.memoryKiB == IdentityKdfProfile.memoryKiB &&
        bootstrap.iterations == IdentityKdfProfile.iterations &&
        bootstrap.parallelism == IdentityKdfProfile.parallelism;
    final v2 =
        bootstrap.profileId == IdentityKdfProfileV2.id &&
        bootstrap.securityVersion == IdentityKdfProfileV2.securityVersion &&
        bootstrap.memoryKiB == IdentityKdfProfileV2.memoryKiB &&
        bootstrap.iterations == IdentityKdfProfileV2.iterations &&
        bootstrap.parallelism == IdentityKdfProfileV2.parallelism;
    if (v2) return IdentityKdfVersion.accountSecretV2;
    if (v1) return IdentityKdfVersion.passwordV1;
    throw const UnsupportedIdentityKdfException('unsupported-kdf-profile');
  }

  /// Unknown accounts receive a same-shaped deterministic pseudo-bootstrap;
  /// running the exact KDF and login path keeps account existence out of the
  /// client's observable behavior. Takes ownership of [accountSecret].
  Future<void> _signIn(
    String email,
    String password,
    LoginKdfBootstrap bootstrap,
    IdentityKdfVersion version,
    Uint8List? accountSecret,
  ) async {
    final salt = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(bootstrap.kdfSalt)),
    );
    final IdentityKdfOutputs outputs;
    try {
      outputs = switch (version) {
        IdentityKdfVersion.passwordV1 => await identityKdfService.derive(
          password: password,
          accountId: bootstrap.accountId,
          kdfSalt: salt,
        ),
        IdentityKdfVersion.accountSecretV2 => await identityKdfService.deriveV2(
          password: password,
          accountId: bootstrap.accountId,
          kdfSalt: salt,
          accountSecret: accountSecret!,
        ),
      };
    } finally {
      salt.fillRange(0, salt.length, 0);
      accountSecret?.fillRange(0, accountSecret.length, 0);
    }
    if (_isCanceled) {
      outputs.dispose();
      return;
    }
    _masterKey?.fillRange(0, _masterKey!.length, 0);
    _masterKey = Uint8List.fromList(outputs.masterKey);
    _accountId = bootstrap.accountId;
    _kdfVersion = version;
    final authCredential = base64Url
        .encode(outputs.authCredential)
        .replaceAll('=', '');
    outputs.dispose();
    final response = await datasource.login(
      email: email,
      authCredential: authCredential,
      kdfVersion: version,
    );

    if (_isCanceled) {
      _clearSecrets();
      return;
    }
    switch (response) {
      case LoginSession(:final session):
        await _establishSession(session);
      case LoginTotpRequired(:final challengeToken):
        AppLogger.i('Login', 'TOTP challenge required');
        _challengeToken = challengeToken;
        emit(const LoginTotpChallenge());
    }
  }

  /// Submits the TOTP (or recovery) code for the pending challenge.
  Future<void> submitTotp(String code) async {
    final challengeToken = _challengeToken;
    if (challengeToken == null || code.isEmpty || _isCanceled) return;
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
      if (!isClosed) {
        emit(const LoginTotpChallenge(error: TotpInvalidException()));
      }
    } on LoginRateLimitedException catch (error) {
      AppLogger.w('Login', 'TOTP verification rate-limited');
      if (!isClosed) emit(LoginTotpChallenge(error: error));
    } catch (e, s) {
      AppLogger.w('Login', 'TOTP verification failed: ${e.runtimeType}');
      _clearSecrets();
      if (!isClosed) emit(LoginFailure(_normalize(e, s)));
    }
  }

  /// Persists the session, derives the master key from the held password,
  /// and emits [LoginSuccess].
  Future<void> _establishSession(PasswordSessionModel session) async {
    if (_isCanceled) {
      _clearSecrets();
      return;
    }
    await tokenStorage.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      userId: session.userId,
      isOnboarded: session.isOnboarded,
    );
    await tokenStorage.setAuthProvider(AuthProviderId.password);

    final newSecret = _newAccountSecret;
    if (newSecret != null && _accountId != null) {
      await accountSecrets.write(_accountId!, newSecret);
    }
    if (_kdfVersion == IdentityKdfVersion.passwordV1) {
      // The security upgrade runs from the unlock screen, where the password
      // is entered once more; no keys are handed to the session here.
      _clearSecrets();
      if (!isClosed) emit(const LoginSucceededLocked());
      return;
    }

    final account = await accountDatasource.getAccount();
    if (_isCanceled) {
      _clearSecrets();
      return;
    }
    final masterKey = _masterKey;
    if (masterKey == null || account.userId != _accountId) {
      throw const UnsupportedIdentityKdfException('account-context-mismatch');
    }
    final encryptedPrivateKey = account.encryptedPrivateKey;
    if (encryptedPrivateKey == null) {
      throw const UnsupportedIdentityKdfException(
        'missing-private-key-material',
      );
    }
    final result = await unlockCryptoService.decryptWithMasterKey(
      masterKey: masterKey,
      encryptedPrivateKeyBase64: encryptedPrivateKey,
    );
    var handedOff = false;
    try {
      if (_isCanceled) return;
      await keyStore.purgeLegacyRawKey();
      if (_isCanceled) return;
      emit(
        LoginSuccess(
          masterKey: result.masterKey,
          privateKey: result.privateKey,
        ),
      );
      handedOff = true;
    } finally {
      _clearSecrets();
      if (!handedOff) {
        result.masterKey.fillRange(0, result.masterKey.length, 0);
        result.privateKey.fillRange(0, result.privateKey.length, 0);
      }
    }
  }

  bool get _isCanceled =>
      isClosed || _biometricGeneration != keyStore.generation;

  /// Drops the in-memory password / challenge token. Strings can't be
  /// zeroed, but dropping every reference lets them be collected.
  void _clearSecrets() {
    _pendingEmail = null;
    _pendingPassword = null;
    _pendingBootstrap = null;
    _kdfVersion = null;
    _newAccountSecret?.fillRange(0, _newAccountSecret!.length, 0);
    _newAccountSecret = null;
    _biometricGeneration = null;
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
    if (error is AccountSecretRequiredException) return error;
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
