import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/exceptions/settings_exceptions.dart';

/// Resolves a [SettingsErrorKind] to a localized, user-facing message.
///
/// Lives at the presentation layer — the data/domain layers only ever
/// carry the typed enum, never user-facing text.
String settingsErrorMessage(AppLocalizations l10n, SettingsErrorKind kind) {
  return switch (kind) {
    SettingsErrorKind.notFound => l10n.settingsErrorNotFound,
    SettingsErrorKind.forbidden => l10n.settingsErrorForbidden,
    SettingsErrorKind.validation => l10n.settingsErrorValidation,
    SettingsErrorKind.networkError => l10n.errorCannotConnectToServer,
    SettingsErrorKind.unknown => l10n.settingsErrorUnknown,
  };
}
