import '../../domain/password_auth_exceptions.dart';

/// Outcome of processing an email-verification token.
enum VerificationStatus {
  /// No token supplied — the page shows the "please verify" gate.
  idle,

  /// Token is being verified.
  verifying,

  /// Token accepted — the account is verified.
  verified,

  /// Token had expired.
  expired,

  /// Token was invalid / already used.
  invalid,

  /// Verification could not be completed (network / protocol).
  serverError,
}

/// Outcome of a "resend verification email" request.
enum ResendStatus {
  /// No resend in flight.
  idle,

  /// A resend request is being sent.
  sending,

  /// The email was (re)sent.
  sent,

  /// Resend failed (network / protocol).
  error,
}

/// Outcome of refreshing the session to check the current verification claim.
enum VerificationCheckStatus { idle, checking, pending, verified, error }

/// State for the verify-email screen. Combines the token-result flow
/// (deep link) and the resend flow (gate) into one immutable value.
class VerifyEmailState {
  const VerifyEmailState({
    this.verification = VerificationStatus.idle,
    this.resend = ResendStatus.idle,
    this.check = VerificationCheckStatus.idle,
    this.serverErrorKind,
  });

  final VerificationStatus verification;
  final ResendStatus resend;
  final VerificationCheckStatus check;

  /// Populated when [verification] is [VerificationStatus.serverError] so
  /// the page can localize the specific network failure.
  final PasswordAuthServerErrorKind? serverErrorKind;

  VerifyEmailState copyWith({
    VerificationStatus? verification,
    ResendStatus? resend,
    VerificationCheckStatus? check,
    PasswordAuthServerErrorKind? serverErrorKind,
    bool clearServerError = false,
  }) {
    return VerifyEmailState(
      verification: verification ?? this.verification,
      resend: resend ?? this.resend,
      check: check ?? this.check,
      serverErrorKind: clearServerError
          ? null
          : (serverErrorKind ?? this.serverErrorKind),
    );
  }
}
