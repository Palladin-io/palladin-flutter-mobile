import '../entities/api_key.dart';
import '../entities/org.dart';

/// Domain contract for organization and API-key management.
///
/// Implemented in the data layer by `SettingsRepositoryImpl`. All
/// failures surface as `SettingsException` with a typed
/// `SettingsErrorKind` so the presentation layer can render localized
/// error messages without leaking transport details.
abstract interface class SettingsRepository {
  /// Fetches the current user's organization.
  Future<Org> getOrg();

  /// Renames the organization. Only the [name] is mutable.
  Future<void> updateOrgName(String name);

  /// Returns every API key (active and revoked) for the organization.
  Future<List<ApiKey>> listApiKeys();

  /// Creates a new API key with the supplied [name].
  ///
  /// Returns a [NewApiKey] carrying the one-time plaintext secret.
  /// SECURITY: the caller must treat the plaintext as in-memory-only —
  /// never persist it.
  Future<NewApiKey> createApiKey(String name);

  /// Revokes an API key by id. Idempotent — revoking an already-revoked
  /// key succeeds without error.
  Future<void> revokeApiKey(String keyId);

  /// Re-activates a previously revoked API key.
  Future<void> activateApiKey(String keyId);

  /// Permanently deletes an API key. Irreversible.
  Future<void> deleteApiKey(String keyId);
}
