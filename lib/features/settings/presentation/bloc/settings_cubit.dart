import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/exceptions/settings_exceptions.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_state.dart';

export 'settings_state.dart';

/// Drives the settings screen — organization details only.
///
/// API-key management has moved to its own standalone screen
/// ([ApiKeysPage]) backed by a dedicated `ApiKeysCubit`. This cubit is
/// now scoped purely to the organization block.
///
/// All errors surface as a typed [SettingsErrorKind] so the UI can
/// render a localized message.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({required this.repository}) : super(const SettingsState());

  final SettingsRepository repository;

  /// Loads the organization section — called once on screen mount.
  Future<void> load() => loadOrg();

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
      AppLogger.e(
        'Settings',
        'Org load failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(
        state.copyWith(
          orgStatus: SectionStatus.error,
          orgError: SettingsErrorKind.unknown,
        ),
      );
    }
  }

  /// Renames the organization. On success the cached [SettingsState.org]
  /// is patched locally so the form reflects the new name without a
  /// refetch.
  Future<void> saveOrgName(String name) async {
    final trimmed = name.trim();
    AppLogger.d('Settings', 'Renaming organization');
    emit(
      state.copyWith(
        isSavingOrg: true,
        clearOrgSaveError: true,
        orgSaveSucceeded: false,
      ),
    );
    try {
      await repository.updateOrgName(trimmed);
      emit(
        state.copyWith(
          isSavingOrg: false,
          org: state.org?.copyWith(name: trimmed),
          orgSaveSucceeded: true,
        ),
      );
    } on SettingsException catch (e) {
      AppLogger.w('Settings', 'Org rename failed: ${e.kind.name}');
      emit(state.copyWith(isSavingOrg: false, orgSaveError: e.kind));
    } catch (e, s) {
      AppLogger.e(
        'Settings',
        'Org rename failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(
        state.copyWith(
          isSavingOrg: false,
          orgSaveError: SettingsErrorKind.unknown,
        ),
      );
    }
  }

  /// Clears the transient org-save result flags after the UI has shown
  /// its snackbar — keeps the flags from re-firing on the next rebuild.
  void acknowledgeOrgSaveResult() {
    if (state.orgSaveError == null && !state.orgSaveSucceeded) return;
    emit(state.copyWith(clearOrgSaveError: true, orgSaveSucceeded: false));
  }
}
