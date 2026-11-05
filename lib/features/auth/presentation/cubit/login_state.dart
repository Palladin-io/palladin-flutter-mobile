import 'dart:typed_data';

/// State for the email + master-password login flow.
sealed class LoginState {
  const LoginState();
}

/// Idle — the form is editable.
final class LoginInitial extends LoginState {
  const LoginInitial();
}

/// A network / crypto step is in progress (salt fetch → authHash → login,
/// or the post-login master-key derivation).
final class LoginLoading extends LoginState {
  const LoginLoading();
}

/// The account has TOTP enabled — the UI shows the 6-digit challenge. The
/// challenge token and the in-memory password are held privately by the
/// cubit. [error] is set when a submitted code was rejected so the user
/// can retry without leaving the challenge.
final class LoginTotpChallenge extends LoginState {
  const LoginTotpChallenge({this.error});

  final Object? error;
}

/// The TOTP code is being verified.
final class LoginTotpVerifying extends LoginState {
  const LoginTotpVerifying();
}

/// Login succeeded and the master key + private key were derived. The
/// page hands these to `AuthBloc` and the router forwards on.
final class LoginSuccess extends LoginState {
  const LoginSuccess({required this.masterKey, required this.privateKey});

  final Uint8List masterKey;
  final Uint8List privateKey;
}

/// This device has no Secret Key for a version-2 account. The page obtains
/// one (QR transfer, Emergency Kit or manual entry) and calls
/// `continueWithSecretKey`; the password stays in cubit memory only.
final class LoginSecretKeyRequired extends LoginState {
  const LoginSecretKeyRequired({required this.accountId, required this.email});

  final String accountId;
  final String email;
}

/// A version-1 account signed in; the session stays locked so the unlock
/// screen runs the security upgrade.
final class LoginSucceededLocked extends LoginState {
  const LoginSucceededLocked();
}

/// Login failed. Carries the typed [error] so the page resolves a
/// localized message.
final class LoginFailure extends LoginState {
  const LoginFailure(this.error);

  final Object error;
}
