import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/api_key.dart';
import '../../domain/exceptions/settings_exceptions.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_state.dart';

export 'settings_state.dart';

/// Drives the settings screen — organization details and API keys.
///
/// The org block and the keys list load independently so a failure in
/// one never blanks the other. All errors surface as a typed
/// [SettingsErrorKind] on the relevant section so the UI can render a
/// localized message.
///
/// SECURITY: the one-time plaintext returned by [createApiKey] is *not*
/// stored on this cubit. It is returned straight to the caller, which
/// holds it in transient widget state until the reveal dialog closes.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({required this.repository}) : super(const SettingsState());

  final SettingsRepository repository;

  /// Loads both sections — called once on screen mount.
  Future<void> load() async {
    await Future.wait([loadOrg(), loadApiKeys()]);
  }

  /// Fetches the organization details.
  Future<void> loadOrg() async {
    AppLogger.d('Settings', 'Loading organization');
    emit(state.copyWith(orgStatus: SectionStatus.loading, clearOrgError: true));
    try {
      final org = await repository.getOrg();
      emit(state.copyWith(orgStatus: SectionStatus.loaded, org: org));
    } on SettingsException catch (e) {
      AppLogger.w('Settings', 'Org load failed: ${e.kind.name}');
      emit(state.copyWith(orgStatus: SectionStatus.error, orgError: e.kind));
    } catch (e, s) {
      AppLogger.e('Settings', 'Org load failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        orgStatus: SectionStatus.error,
        orgError: SettingsErrorKind.unknown,
      ));
    }
  }

  /// Fetches the API-key list.
  Future<void> loadApiKeys() async {
    AppLogger.d('Settings', 'Loading API keys');
    emit(state.copyWith(
      keysStatus: SectionStatus.loading,
      clearKeysError: true,
    ));
    try {
      final keys = await repository.listApiKeys();
      AppLogger.i('Settings', 'Loaded ${keys.length} API keys');
      emit(state.copyWith(keysStatus: SectionStatus.loaded, apiKeys: keys));
    } on SettingsException catch (e) {
      AppLogger.w('Settings', 'API key load failed: ${e.kind.name}');
      emit(state.copyWith(keysStatus: SectionStatus.error, keysError: e.kind));
    } catch (e, s) {
      AppLogger.e('Settings', 'API key load failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        keysStatus: SectionStatus.error,
        keysError: SettingsErrorKind.unknown,
      ));
    }
  }

  /// Renames the organization. On success the cached [SettingsState.org]
  /// is patched locally so the form reflects the new name without a
  /// refetch.
  Future<void> saveOrgName(String name) async {
    final trimmed = name.trim();
    AppLogger.d('Settings', 'Renaming organization');
    emit(state.copyWith(
      isSavingOrg: true,
      clearOrgSaveError: true,
      orgSaveSucceeded: false,
    ));
    try {
      await repository.updateOrgName(trimmed);
      AnalyticsService.instance.capture('settings', 'org-renamed');
      emit(state.copyWith(
        isSavingOrg: false,
        org: state.org?.copyWith(name: trimmed),
        orgSaveSucceeded: true,
      ));
    } on SettingsException catch (e) {
      AppLogger.w('Settings', 'Org rename failed: ${e.kind.name}');
      emit(state.copyWith(isSavingOrg: false, orgSaveError: e.kind));
    } catch (e, s) {
      AppLogger.e('Settings', 'Org rename failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        isSavingOrg: false,
        orgSaveError: SettingsErrorKind.unknown,
      ));
    }
  }

  /// Clears the transient org-save result flags after the UI has shown
  /// its snackbar — keeps the flags from re-firing on the next rebuild.
  void acknowledgeOrgSaveResult() {
    if (state.orgSaveError == null && !state.orgSaveSucceeded) return;
    emit(state.copyWith(clearOrgSaveError: true, orgSaveSucceeded: false));
  }

  /// Creates a new API key and returns the one-time [NewApiKey].
  ///
  /// SECURITY: the returned value carries the plaintext secret. It is
  /// deliberately *not* stored on the cubit — the caller must hold it in
  /// transient widget state and discard it when the reveal dialog
  /// closes. On success the metadata-only list is refreshed.
  ///
  /// Throws [SettingsException] on failure so the calling dialog can
  /// render an inline error.
  Future<NewApiKey> createApiKey(String name) async {
    AppLogger.d('Settings', 'Creating API key');
    final created = await repository.createApiKey(name.trim());
    AnalyticsService.instance.capture('settings', 'api-key-created');
    await loadApiKeys();
    return created;
  }

  /// Revokes an API key, then refreshes the list.
  Future<void> revokeApiKey(String keyId) async {
    AppLogger.d('Settings', 'Revoking API key');
    try {
      await repository.revokeApiKey(keyId);
      AnalyticsService.instance.capture('settings', 'api-key-revoked');
      await loadApiKeys();
    } on SettingsException catch (e) {
      AppLogger.w('Settings', 'API key revoke failed: ${e.kind.name}');
      emit(state.copyWith(keysStatus: SectionStatus.error, keysError: e.kind));
    } catch (e, s) {
      AppLogger.e('Settings', 'API key revoke failed unexpectedly',
          error: e, stackTrace: s);
      emit(state.copyWith(
        keysStatus: SectionStatus.error,
        keysError: SettingsErrorKind.unknown,
      ));
    }
  }
}
