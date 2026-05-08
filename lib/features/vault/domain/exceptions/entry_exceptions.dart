/// Typed exceptions for the entry sub-feature inside the vault module.
///
/// Mirrors the pattern used by `VaultException` — no user-facing text
/// in the data/domain layer; the presentation layer maps these to
/// localized messages via `AppLocalizations`.
library;

/// Classifies all entry-related failures so the UI can resolve the
/// correct localized message.
enum EntryErrorKind {
  /// 404 from the backend — the entry no longer exists or the caller
  /// has no visibility into it.
  notFound,

  /// 403 — the caller is not allowed to perform this action.
  forbidden,

  /// 400 — request body failed validation (label too long, missing
  /// blob, …). Surfaces as a generic error in the UI for now.
  validation,

  /// Crypto failure — either the wrappedVK could not be unwrapped with
  /// the user's private key (vault membership broken) or the per-entry
  /// blob's MAC verification failed (tampered ciphertext / wrong VK).
  cryptoFailure,

  /// Connection / timeout / send-failure on the wire.
  networkError,

  /// Any other unexpected failure (5xx, invalid response shape, etc.).
  unknown,
}

/// Thrown by the entry repository on any failure.
///
/// Carries a typed [kind] so the presentation layer can resolve the
/// appropriate localized message without embedding user-facing text in
/// the data layer.
class EntryException implements Exception {
  const EntryException(this.kind);

  final EntryErrorKind kind;

  @override
  String toString() => 'EntryException(${kind.name})';
}
