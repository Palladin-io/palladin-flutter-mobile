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
    this.mutationError,
    this.revokingKeyId,
    this.activatingKeyId,
    this.deletingKeyId,
  });

  /// Load status of the list.
  final ApiKeysStatus status;

  /// All API keys (active and revoked) for the organization.
  final List<ApiKey> apiKeys;

  /// Set when the initial list load failed — drives the full-screen
  /// error state.
  final SettingsErrorKind? error;

  /// Transient error from a revoke / activate / delete mutation. Unlike
  /// [error] this does *not* replace the screen — the detail page shows
  /// it as a snackbar so the key card stays visible, then calls
  /// [ApiKeysCubit.acknowledgeMutationError] to clear it.
  final SettingsErrorKind? mutationError;

  /// Id of the key currently being revoked, or `null` when no revoke is
  /// in flight — lets the detail page disable its Revoke button and show
  /// a spinner without a separate boolean.
  final String? revokingKeyId;

  /// Id of the key currently being activated, or `null` when no activate
  /// is in flight.
  final String? activatingKeyId;

  /// Id of the key currently being permanently deleted, or `null` when no
  /// delete is in flight.
  final String? deletingKeyId;

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
    SettingsErrorKind? mutationError,
    bool clearMutationError = false,
    String? revokingKeyId,
    bool clearRevokingKeyId = false,
    String? activatingKeyId,
    bool clearActivatingKeyId = false,
    String? deletingKeyId,
    bool clearDeletingKeyId = false,
  }) {
    return ApiKeysState(
      status: status ?? this.status,
      apiKeys: apiKeys ?? this.apiKeys,
      error: clearError ? null : (error ?? this.error),
      mutationError:
          clearMutationError ? null : (mutationError ?? this.mutationError),
      revokingKeyId:
          clearRevokingKeyId ? null : (revokingKeyId ?? this.revokingKeyId),
      activatingKeyId: clearActivatingKeyId
          ? null
          : (activatingKeyId ?? this.activatingKeyId),
      deletingKeyId:
          clearDeletingKeyId ? null : (deletingKeyId ?? this.deletingKeyId),
    );
  }
}
