import '../../domain/entities/org.dart';
import '../../domain/exceptions/settings_exceptions.dart';

/// Loading status of the organization section of the settings screen.
enum SectionStatus { initial, loading, loaded, error }

/// Immutable state for the settings screen.
///
/// The settings screen now owns only the organization block — API-key
/// management has moved to its own standalone screen ([ApiKeysPage])
/// driven by a dedicated `ApiKeysCubit`. Keeping the two concerns on
/// separate cubits means a failure in one never blanks the other and
/// each screen mounts only the state it needs.
class SettingsState {
  const SettingsState({
    this.orgStatus = SectionStatus.initial,
    this.org,
    this.orgError,
    this.isSavingOrg = false,
    this.orgSaveError,
    this.orgSaveSucceeded = false,
  });

  // ── Organization section ────────────────────────────────────────────
  final SectionStatus orgStatus;
  final Org? org;
  final SettingsErrorKind? orgError;

  /// True while a `PUT /api/org` rename is in flight.
  final bool isSavingOrg;

  /// Set when the most recent rename failed — consumed and cleared by
  /// the UI after it shows a snackbar.
  final SettingsErrorKind? orgSaveError;

  /// Set when the most recent rename succeeded — consumed and cleared by
  /// the UI after it shows a snackbar.
  final bool orgSaveSucceeded;

  SettingsState copyWith({
    SectionStatus? orgStatus,
    Org? org,
    SettingsErrorKind? orgError,
    bool clearOrgError = false,
    bool? isSavingOrg,
    SettingsErrorKind? orgSaveError,
    bool clearOrgSaveError = false,
    bool? orgSaveSucceeded,
  }) {
    return SettingsState(
      orgStatus: orgStatus ?? this.orgStatus,
      org: org ?? this.org,
      orgError: clearOrgError ? null : (orgError ?? this.orgError),
      isSavingOrg: isSavingOrg ?? this.isSavingOrg,
      orgSaveError:
          clearOrgSaveError ? null : (orgSaveError ?? this.orgSaveError),
      orgSaveSucceeded: orgSaveSucceeded ?? this.orgSaveSucceeded,
    );
  }
}
