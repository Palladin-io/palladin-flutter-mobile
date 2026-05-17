import '../../../settings/domain/entities/api_key.dart';
import '../../../settings/domain/exceptions/settings_exceptions.dart';

/// Loading status of the API-keys list.
enum ApiKeysStatus { initial, loading, loaded, error }

/// Immutable state for the standalone API-keys screen.
///
/// Drives both the list page ([ApiKeysPage]) and the detail page
/// ([ApiKeyDetailPage]) — the detail page resolves its key from
/// [apiKeys] by id so the two surfaces always agree (e.g. a revoke on
/// the detail page is reflected in the list without a refetch).
class ApiKeysState {
  const ApiKeysState({
    this.status = ApiKeysStatus.initial,
    this.apiKeys = const [],
    this.error,
    this.revokingKeyId,
  });

  /// Load status of the list.
  final ApiKeysStatus status;

  /// All API keys (active and revoked) for the organization.
  final List<ApiKey> apiKeys;

  /// Set when the list load or a revoke failed.
  final SettingsErrorKind? error;

  /// Id of the key currently being revoked, or `null` when no revoke is
  /// in flight — lets the detail page disable its Revoke button and show
  /// a spinner without a separate boolean.
  final String? revokingKeyId;

  /// Resolves a single key by id, or `null` if it is not in the list.
  ApiKey? keyById(String keyId) {
    for (final key in apiKeys) {
      if (key.apiKeyId == keyId) return key;
    }
    return null;
  }

  ApiKeysState copyWith({
    ApiKeysStatus? status,
    List<ApiKey>? apiKeys,
    SettingsErrorKind? error,
    bool clearError = false,
    String? revokingKeyId,
    bool clearRevokingKeyId = false,
  }) {
    return ApiKeysState(
      status: status ?? this.status,
      apiKeys: apiKeys ?? this.apiKeys,
      error: clearError ? null : (error ?? this.error),
      revokingKeyId:
          clearRevokingKeyId ? null : (revokingKeyId ?? this.revokingKeyId),
    );
  }
}
