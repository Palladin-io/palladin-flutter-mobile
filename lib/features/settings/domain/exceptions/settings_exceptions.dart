/// Typed exceptions for the settings feature (org + API keys).
///
/// Mirrors the pattern used by vault/unlock/onboarding — no user-facing
/// text in the data/domain layer. The presentation layer maps these to
/// localized messages via `AppLocalizations`.
library;

/// Classifies all settings-related failures so the UI can resolve the
/// correct localized message.
enum SettingsErrorKind {
  /// 404 from the backend — the resource no longer exists or is not
  /// visible to the caller.
  notFound,

  /// 403 from the backend — the caller is not allowed to perform the
  /// requested action.
  forbidden,

  /// 400 from the backend — the submitted payload failed validation.
  validation,

  /// 409 from the backend — state changed, the resource is still in use, or
  /// a plan/security transition prevents the requested mutation.
  conflict,

  /// The organization has no free human-user seat. The backend remains the
  /// authoritative arbiter because cached seat usage can change concurrently.
  seatLimitReached,

  /// Backend fail-closed boundary while GrantManage recipient-set changes are
  /// unavailable. The UI must keep the unsaved role draft intact.
  grantManageCutoverUnavailable,

  /// Connection / timeout / send-failure on the wire.
  networkError,

  /// Any other unexpected failure (5xx, invalid response shape, etc.).
  unknown,
}

/// Thrown by the settings repository on any failure.
///
/// Carries a typed [kind] so the presentation layer can resolve the
/// appropriate localized message without embedding user-facing text in
/// the data layer.
class SettingsException implements Exception {
  const SettingsException(this.kind);

  final SettingsErrorKind kind;

  @override
  String toString() => 'SettingsException(${kind.name})';
}
