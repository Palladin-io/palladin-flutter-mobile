import '../../domain/entities/api_key.dart';
import '../../domain/entities/org.dart';
import '../../domain/exceptions/settings_exceptions.dart';

/// Loading status of an independently-fetched section of the settings
/// screen (the org block and the API-keys list each track their own).
enum SectionStatus { initial, loading, loaded, error }

/// Immutable state for the settings screen.
///
/// The screen has two independently-loaded sections — the organization
/// block and the API-keys list — so each carries its own
/// [SectionStatus]. A single sealed hierarchy would force both sections
/// to share one loading/error state, which would (for example) hide the
/// org form whenever the key list failed.
class SettingsState {
  const SettingsState({
    this.orgStatus = SectionStatus.initial,
    this.org,
    this.orgError,
    this.keysStatus = SectionStatus.initial,
    this.apiKeys = const [],
    this.keysError,
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

  // ── API keys section ────────────────────────────────────────────────
  final SectionStatus keysStatus;
  final List<ApiKey> apiKeys;
  final SettingsErrorKind? keysError;

  SettingsState copyWith({
    SectionStatus? orgStatus,
    Org? org,
    SettingsErrorKind? orgError,
    bool clearOrgError = false,
    SectionStatus? keysStatus,
    List<ApiKey>? apiKeys,
    SettingsErrorKind? keysError,
    bool clearKeysError = false,
    bool? isSavingOrg,
    SettingsErrorKind? orgSaveError,
    bool clearOrgSaveError = false,
    bool? orgSaveSucceeded,
  }) {
    return SettingsState(
      orgStatus: orgStatus ?? this.orgStatus,
      org: org ?? this.org,
      orgError: clearOrgError ? null : (orgError ?? this.orgError),
      keysStatus: keysStatus ?? this.keysStatus,
      apiKeys: apiKeys ?? this.apiKeys,
      keysError: clearKeysError ? null : (keysError ?? this.keysError),
      isSavingOrg: isSavingOrg ?? this.isSavingOrg,
      orgSaveError:
          clearOrgSaveError ? null : (orgSaveError ?? this.orgSaveError),
      orgSaveSucceeded: orgSaveSucceeded ?? this.orgSaveSucceeded,
    );
  }
}
