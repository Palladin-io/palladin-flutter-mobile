/// Typed exceptions for the agents feature.
///
/// Mirrors the pattern used by settings/vault/unlock — no user-facing
/// text in the data/domain layer. The presentation layer maps these to
/// localized messages via `AppLocalizations`.
library;

/// Classifies all agent-related failures so the UI can resolve the
/// correct localized message.
enum AgentsErrorKind {
  /// 404 from the backend — the agent no longer exists or is not
  /// visible to the caller.
  notFound,

  /// 403 from the backend — the caller is not allowed to perform the
  /// requested action.
  forbidden,

  /// 400 from the backend — the submitted payload failed validation.
  validation,

  /// Connection / timeout / send-failure on the wire.
  networkError,

  /// Any other unexpected failure (5xx, invalid response shape, etc.).
  unknown,
}

/// Thrown by the agents repository on any failure.
///
/// Carries a typed [kind] so the presentation layer can resolve the
/// appropriate localized message without embedding user-facing text in
/// the data layer.
class AgentsException implements Exception {
  const AgentsException(this.kind);

  final AgentsErrorKind kind;

  @override
  String toString() => 'AgentsException(${kind.name})';
}
