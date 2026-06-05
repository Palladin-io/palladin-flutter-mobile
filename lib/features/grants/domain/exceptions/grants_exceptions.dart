/// Typed exceptions for the grants feature.
///
/// Mirrors the pattern used by agents/vault/unlock — no user-facing text
/// in the data/domain layer. The presentation layer maps these to
/// localized messages via `AppLocalizations`.
library;

/// Classifies all grant-related failures so the UI can resolve the
/// correct localized message.
enum GrantsErrorKind {
  /// 404 — the grant or vault no longer exists or is not visible.
  notFound,

  /// 403 — the caller lacks the `GrantManage` permission.
  forbidden,

  /// 400 / 409 — the submitted payload failed validation (e.g. neither
  /// or both of expiry/limit supplied, grant not pending, wrong mode).
  validation,

  /// Connection / timeout / send-failure on the wire.
  networkError,

  /// On-device crypto failure while producing the approval envelope
  /// (VK unwrap, entry decrypt, or sealing the DEK).
  cryptoFailure,

  /// Any other unexpected failure (5xx, invalid response shape, etc.).
  unknown,
}

/// Thrown by the grants repository / crypto service on any failure.
///
/// Carries a typed [kind] so the presentation layer can resolve the
/// appropriate localized message without embedding user-facing text in
/// the data layer.
class GrantsException implements Exception {
  const GrantsException(this.kind);

  final GrantsErrorKind kind;

  @override
  String toString() => 'GrantsException(${kind.name})';
}
