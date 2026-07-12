/// State for the TOTP enrollment flow (CVT-274).
sealed class TotpEnrollState {
  const TotpEnrollState();
}

/// Requesting the secret + otpauth URI from the backend.
final class TotpEnrollLoading extends TotpEnrollState {
  const TotpEnrollLoading();
}

/// The secret is ready to display (QR + manual code). [error] is set when
/// a submitted confirmation code was rejected so the user can retry.
final class TotpEnrollReady extends TotpEnrollState {
  const TotpEnrollReady({
    required this.secret,
    required this.otpauthUri,
    this.confirming = false,
    this.error,
  });

  final String secret;
  final String otpauthUri;

  /// Whether a confirmation code is currently being verified.
  final bool confirming;

  /// Set when the last confirmation attempt was rejected.
  final Object? error;

  TotpEnrollReady copyWith({bool? confirming, Object? error, bool clearError = false}) {
    return TotpEnrollReady(
      secret: secret,
      otpauthUri: otpauthUri,
      confirming: confirming ?? this.confirming,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// The initial enroll request failed (network / protocol). Carries the
/// typed [error] for localization; the page offers a retry.
final class TotpEnrollLoadFailed extends TotpEnrollState {
  const TotpEnrollLoadFailed(this.error);

  final Object error;
}

/// TOTP is enabled. [recoveryCodes] are shown **once** — the user must
/// save them before leaving.
final class TotpEnrollConfirmed extends TotpEnrollState {
  const TotpEnrollConfirmed(this.recoveryCodes);

  final List<String> recoveryCodes;
}
