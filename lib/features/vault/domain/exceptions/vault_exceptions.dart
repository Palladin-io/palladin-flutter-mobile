/// Typed exceptions for the vault feature.
///
/// Mirrors the pattern used by unlock/onboarding/recovery — no
/// user-facing text in the data/domain layer. The presentation layer
/// maps these to localized messages via `AppLocalizations`.
library;

/// Classifies all vault-related failures so the UI can resolve the
/// correct localized message and analytics reason.
enum VaultErrorKind {
  /// 404 from the backend — the vault no longer exists or the caller
  /// has no visibility into it.
  notFound,

  /// 403 with a "permission denied" body — the caller is not allowed
  /// to perform the requested action on this vault.
  forbidden,

  /// 403 with a "plan limit reached" body — the user has hit the
  /// number-of-vaults cap for their billing plan.
  planLimitReached,

  /// 403 with a "full mode not allowed" body — the user's plan does
  /// not allow creating Full-mode vaults.
  fullModeNotAllowed,

  /// Connection / timeout / send-failure on the wire.
  networkError,

  /// Any other unexpected failure (5xx, invalid response shape, etc.).
  unknown,
}

/// Thrown by the vault repository on any failure.
///
/// Carries a typed [kind] so the presentation layer can resolve the
/// appropriate localized message without embedding user-facing text in
/// the data layer.
class VaultException implements Exception {
  const VaultException(this.kind);

  final VaultErrorKind kind;

  @override
  String toString() => 'VaultException(${kind.name})';
}
