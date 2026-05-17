/// Lifecycle status of an API key.
///
/// Mirrors the backend's string `status` field — `"Active"` / `"Revoked"`.
enum ApiKeyStatus {
  /// The key is usable by agents.
  active,

  /// The key has been revoked and can no longer authenticate.
  revoked,
}

extension ApiKeyStatusExtension on ApiKeyStatus {
  /// Maps the backend's string `status` to the typed enum. Unknown
  /// values fall back to [ApiKeyStatus.revoked] — failing closed keeps
  /// a malformed payload from rendering a key as usable.
  static ApiKeyStatus fromWire(String value) =>
      value.toLowerCase() == 'active'
          ? ApiKeyStatus.active
          : ApiKeyStatus.revoked;
}

/// Domain representation of a single API key (metadata only).
///
/// SECURITY: this entity never carries the plaintext secret. The
/// plaintext is returned exactly once by `POST /api/api-keys` and is
/// modelled separately by [NewApiKey]. Listing keys only ever exposes
/// non-sensitive metadata.
class ApiKey {
  const ApiKey({
    required this.apiKeyId,
    required this.name,
    required this.status,
    required this.createdAt,
    this.revokedAt,
  });

  /// Stable, server-issued identifier.
  final String apiKeyId;

  /// User-supplied label for the key.
  final String name;

  /// Current lifecycle status — see [ApiKeyStatus].
  final ApiKeyStatus status;

  /// When the key was created.
  final DateTime createdAt;

  /// When the key was revoked, or `null` if it is still active.
  final DateTime? revokedAt;

  bool get isActive => status == ApiKeyStatus.active;
}

/// A freshly created API key, including its one-time plaintext secret.
///
/// SECURITY: [plaintext] is the only time the secret is ever exposed by
/// the backend. It must be held in memory only — never written to
/// SharedPreferences, secure storage, logs, or analytics. Discard the
/// instance as soon as the user dismisses the reveal dialog.
class NewApiKey {
  const NewApiKey({
    required this.apiKeyId,
    required this.name,
    required this.plaintext,
    required this.createdAt,
  });

  /// Stable, server-issued identifier.
  final String apiKeyId;

  /// User-supplied label for the key.
  final String name;

  /// The plaintext secret — shown to the user exactly once.
  final String plaintext;

  /// When the key was created.
  final DateTime createdAt;
}
