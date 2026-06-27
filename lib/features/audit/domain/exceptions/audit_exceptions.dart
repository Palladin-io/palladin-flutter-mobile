/// Typed error semantics for the audit feature.
///
/// The data layer maps transport failures (DioException, parse errors)
/// onto an [AuditErrorKind]; the presentation layer translates the kind
/// to a localized message where `BuildContext` is available. This keeps
/// user-facing strings out of the data/domain layers.
enum AuditErrorKind {
  /// Caller lacks the `AuditView` permission (HTTP 403).
  forbidden,

  /// The vault was not found or the caller is not a member (HTTP 404).
  notFound,

  /// Connectivity / timeout / unreachable host.
  networkError,

  /// Anything else (5xx, malformed payload…).
  unknown,
}

/// Thrown by the audit repository. Carries a typed [kind] only — no raw
/// transport details leak to the presentation layer.
class AuditException implements Exception {
  const AuditException(this.kind);

  final AuditErrorKind kind;

  @override
  String toString() => 'AuditException(${kind.name})';
}
