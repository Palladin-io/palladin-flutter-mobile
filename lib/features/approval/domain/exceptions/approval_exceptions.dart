/// Typed exceptions for the approval flow.
///
/// No user-facing text in the data/domain layer — the presentation layer
/// maps these to localized messages via `AppLocalizations`.
library;

/// Classifies all approval-flow failures.
enum ApprovalErrorKind {
  /// 404 — the grant / entry / vault no longer exists.
  notFound,

  /// 403 — the caller lacks the `GrantManage` permission.
  forbidden,

  /// 400 / 409 — payload rejected (grant not pending, not granular,
  /// neither/both of expiry+limit supplied, …).
  validation,

  /// 409 — the reviewed Entry/grant/Agent state changed; review must restart.
  conflict,

  /// Connection / timeout / send-failure on the wire.
  networkError,

  /// On-device crypto failure while producing the approval envelope.
  cryptoFailure,

  /// The vault is locked — no in-memory private key available to unwrap
  /// the VK, so the envelope cannot be produced.
  vaultLocked,

  /// Any other unexpected failure.
  unknown,
}

/// Thrown by the approval repository / crypto service on any failure.
class ApprovalException implements Exception {
  const ApprovalException(this.kind);

  final ApprovalErrorKind kind;

  @override
  String toString() => 'ApprovalException(${kind.name})';
}
