import '../../../../l10n/generated/app_localizations.dart';
import '../../data/import/import_models.dart';
import '../cubit/import_wizard_state.dart';

/// Presentation-layer copy for the import wizard: maps typed enums onto
/// localized strings so no user-facing text lives in the data/cubit layer.
class ImportWizardCopy {
  ImportWizardCopy._();

  /// Human-readable source manager / format label for a badge.
  static String formatName(AppLocalizations l10n, ImportFormat format) =>
      switch (format) {
        ImportFormat.genericCsv => l10n.importFormatGeneric,
        ImportFormat.firefoxCsv => 'Firefox',
        ImportFormat.safariCsv => 'Safari',
        ImportFormat.bitwardenJson => 'Bitwarden',
        ImportFormat.bitwardenCsv => 'Bitwarden',
        ImportFormat.lastpassCsv => 'LastPass',
        ImportFormat.onePasswordCsv => '1Password',
        ImportFormat.onePassword1pux => '1Password',
        ImportFormat.dashlaneCsv => 'Dashlane',
        ImportFormat.dashlaneZip => 'Dashlane',
        ImportFormat.keepassXml => 'KeePass',
        ImportFormat.nordpassCsv => 'NordPass',
        ImportFormat.keeperJson => 'Keeper',
        ImportFormat.protonPassJson => 'Proton Pass',
        ImportFormat.enpassJson => 'Enpass',
        ImportFormat.roboformCsv => 'RoboForm',
        ImportFormat.palladinJson => 'Palladin',
        ImportFormat.palladinCsv => 'Palladin',
        ImportFormat.manualCsv => l10n.importFormatManual,
      };

  static String failureMessage(
    AppLocalizations l10n,
    ImportFailureReason reason,
  ) => switch (reason) {
    ImportFailureReason.emptyFile => l10n.importErrorEmpty,
    ImportFailureReason.encryptedFile => l10n.importErrorEncrypted,
    ImportFailureReason.unrecognisedFile => l10n.importErrorUnrecognised,
    ImportFailureReason.noEntries => l10n.importErrorNoEntries,
    ImportFailureReason.crypto => l10n.importErrorCrypto,
    ImportFailureReason.network => l10n.importErrorNetwork,
    ImportFailureReason.unknown => l10n.importErrorUnknown,
  };

  static String conflictStrategyLabel(
    AppLocalizations l10n,
    ImportConflictStrategy strategy,
  ) => switch (strategy) {
    ImportConflictStrategy.skip => l10n.importStrategySkip,
    ImportConflictStrategy.overwrite => l10n.importStrategyOverwrite,
    ImportConflictStrategy.rename => l10n.importStrategyRename,
  };
}
