/// State for the TOTP enrollment flow.
sealed class TotpEnrollState {
  const TotpEnrollState();
}

/// The current login password is needed before enrollment can start.
/// [verifying] covers derivation and the enroll request; [error] is the
/// typed failure of the previous attempt.
final class TotpEnrollPasswordRequired extends TotpEnrollState {
  const TotpEnrollPasswordRequired({this.verifying = false, this.error});

  final bool verifying;
  final Object? error;
}

/// The account has no password login credential, so TOTP cannot protect it.
final class TotpEnrollUnavailable extends TotpEnrollState {
  const TotpEnrollUnavailable();
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

  TotpEnrollReady copyWith({
    bool? confirming,
    Object? error,
    bool clearError = false,
  }) {
    return TotpEnrollReady(
      secret: secret,
      otpauthUri: otpauthUri,
      confirming: confirming ?? this.confirming,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// TOTP is enabled. [recoveryCodes] are shown **once** — the user must
/// save them before leaving.
final class TotpEnrollConfirmed extends TotpEnrollState {
  const TotpEnrollConfirmed(this.recoveryCodes);

  final List<String> recoveryCodes;
}
