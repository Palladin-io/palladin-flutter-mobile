import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../settings/domain/entities/api_key.dart';
import '../../../settings/domain/exceptions/settings_exceptions.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import 'api_keys_state.dart';

export 'api_keys_state.dart';

/// Drives the standalone API-keys feature — the list screen
/// ([ApiKeysPage]) and the detail screen ([ApiKeyDetailPage]).
///
/// Reuses [SettingsRepository] for the API-key endpoints — the data and
/// domain layers stay shared with the settings feature; only the
/// presentation layer is split so each screen mounts its own cubit.
///
/// SECURITY: the one-time plaintext returned by [createApiKey] is *not*
/// stored on this cubit. It is returned straight to the caller, which
/// holds it in transient widget state until the reveal sheet closes.
class ApiKeysCubit extends Cubit<ApiKeysState> {
  ApiKeysCubit({required this.repository}) : super(const ApiKeysState());

  final SettingsRepository repository;

  /// Fetches the API-key list — called once on screen mount.
  Future<void> load() async {
    AppLogger.d('ApiKeys', 'Loading API keys');
    emit(state.copyWith(status: ApiKeysStatus.loading, clearError: true));
    try {
      final keys = await repository.listApiKeys();
      AppLogger.i('ApiKeys', 'Loaded ${keys.length} API keys');
      emit(state.copyWith(status: ApiKeysStatus.loaded, apiKeys: keys));
    } on SettingsException catch (e) {
      AppLogger.w('ApiKeys', 'API key load failed: ${e.kind.name}');
      emit(state.copyWith(status: ApiKeysStatus.error, error: e.kind));
    } catch (e, s) {
      AppLogger.e('ApiKeys', 'API key load failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: ApiKeysStatus.error,
        error: SettingsErrorKind.unknown,
      ));
    }
  }

  /// Creates a new API key and returns the one-time [NewApiKey].
  ///
  /// SECURITY: the returned value carries the plaintext secret. It is
  /// deliberately *not* stored on the cubit — the caller must hold it in
  /// transient widget state and discard it when the reveal sheet closes.
  /// On success the metadata-only list is refreshed.
  ///
  /// Throws [SettingsException] on failure so the calling sheet can
  /// render an inline error.
  Future<NewApiKey> createApiKey(String name) async {
    AppLogger.d('ApiKeys', 'Creating API key');
    final created = await repository.createApiKey(name.trim());
    AnalyticsService.instance.capture('settings', 'api-key-created');
    await load();
    return created;
  }

  /// Revokes an API key, then refreshes the list.
  Future<void> revokeApiKey(String keyId) async {
    AppLogger.d('ApiKeys', 'Revoking API key');
    emit(state.copyWith(revokingKeyId: keyId, clearError: true));
    try {
      await repository.revokeApiKey(keyId);
      AnalyticsService.instance.capture('settings', 'api-key-revoked');
      final keys = await repository.listApiKeys();
      emit(state.copyWith(
        status: ApiKeysStatus.loaded,
        apiKeys: keys,
        clearRevokingKeyId: true,
      ));
    } on SettingsException catch (e) {
      AppLogger.w('ApiKeys', 'API key revoke failed: ${e.kind.name}');
      emit(state.copyWith(
        status: ApiKeysStatus.error,
        error: e.kind,
        clearRevokingKeyId: true,
      ));
    } catch (e, s) {
      AppLogger.e('ApiKeys', 'API key revoke failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: ApiKeysStatus.error,
        error: SettingsErrorKind.unknown,
        clearRevokingKeyId: true,
      ));
    }
  }

  /// Re-activates a revoked API key, then refreshes the list.
  Future<void> activateApiKey(String keyId) async {
    AppLogger.d('ApiKeys', 'Activating API key');
    emit(state.copyWith(activatingKeyId: keyId, clearError: true));
    try {
      await repository.activateApiKey(keyId);
      AnalyticsService.instance.capture('settings', 'api-key-activated');
      final keys = await repository.listApiKeys();
      emit(state.copyWith(
        status: ApiKeysStatus.loaded,
        apiKeys: keys,
        clearActivatingKeyId: true,
      ));
    } on SettingsException catch (e) {
      AppLogger.w('ApiKeys', 'API key activate failed: ${e.kind.name}');
      emit(state.copyWith(
        status: ApiKeysStatus.error,
        error: e.kind,
        clearActivatingKeyId: true,
      ));
    } catch (e, s) {
      AppLogger.e('ApiKeys', 'API key activate failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: ApiKeysStatus.error,
        error: SettingsErrorKind.unknown,
        clearActivatingKeyId: true,
      ));
    }
  }

  /// Permanently deletes an API key, then refreshes the list.
  Future<void> deleteApiKey(String keyId) async {
    AppLogger.d('ApiKeys', 'Permanently deleting API key');
    emit(state.copyWith(deletingKeyId: keyId, clearError: true));
    try {
      await repository.deleteApiKey(keyId);
      AnalyticsService.instance.capture('settings', 'api-key-deleted');
      final keys = await repository.listApiKeys();
      emit(state.copyWith(
        status: ApiKeysStatus.loaded,
        apiKeys: keys,
        clearDeletingKeyId: true,
      ));
    } on SettingsException catch (e) {
      AppLogger.w('ApiKeys', 'API key delete failed: ${e.kind.name}');
      emit(state.copyWith(
        status: ApiKeysStatus.error,
        error: e.kind,
        clearDeletingKeyId: true,
      ));
    } catch (e, s) {
      AppLogger.e('ApiKeys', 'API key delete failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        status: ApiKeysStatus.error,
        error: SettingsErrorKind.unknown,
        clearDeletingKeyId: true,
      ));
    }
  }
}
