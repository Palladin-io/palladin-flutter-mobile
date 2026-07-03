import '../../data/import/import_models.dart';
import '../../domain/entities/entry_entity.dart';

/// How to resolve an imported entry whose label collides with an existing
/// entry in the target vault.
enum ImportConflictStrategy {
  /// Drop the imported entry, keep the existing one.
  skip,

  /// Replace the existing entry's payload with the imported one.
  overwrite,

  /// Keep both — import under a suffixed label.
  rename,
}

/// One row in the preview list: a parsed entry, whether it collides with
/// an existing entry, and whether the user chose to include it.
class ImportPreviewItem {
  const ImportPreviewItem({
    required this.parsed,
    this.conflict,
    this.included = true,
  });

  final ParsedEntry parsed;

  /// The existing entry sharing this label, or `null` when there is no
  /// collision.
  final EntryEntity? conflict;

  final bool included;

  bool get hasConflict => conflict != null;

  ImportPreviewItem copyWith({bool? included}) => ImportPreviewItem(
        parsed: parsed,
        conflict: conflict,
        included: included ?? this.included,
      );
}

sealed class ImportWizardState {
  const ImportWizardState();
}

/// Idle — waiting for the user to pick a file (and, for the global entry
/// point, a target vault).
final class ImportWizardInitial extends ImportWizardState {
  const ImportWizardInitial();
}

/// Parsing the picked file and detecting conflicts against the vault.
final class ImportWizardParsing extends ImportWizardState {
  const ImportWizardParsing();
}

/// The CSV matched no known profile — the user must map columns.
final class ImportWizardNeedsMapping extends ImportWizardState {
  const ImportWizardNeedsMapping(this.table);

  final CsvTable table;
}

/// Parsed successfully — showing the preview before commit.
final class ImportWizardPreview extends ImportWizardState {
  const ImportWizardPreview({
    required this.format,
    required this.items,
    required this.skippedCount,
    required this.conflictStrategy,
  });

  final ImportFormat format;
  final List<ImportPreviewItem> items;

  /// Non-login items dropped during parsing.
  final int skippedCount;

  /// Global strategy applied to every conflicting item.
  final ImportConflictStrategy conflictStrategy;

  int get includedCount => items.where((i) => i.effectiveIncluded(conflictStrategy)).length;
  int get conflictCount => items.where((i) => i.hasConflict).length;

  ImportWizardPreview copyWith({
    List<ImportPreviewItem>? items,
    ImportConflictStrategy? conflictStrategy,
  }) =>
      ImportWizardPreview(
        format: format,
        items: items ?? this.items,
        skippedCount: skippedCount,
        conflictStrategy: conflictStrategy ?? this.conflictStrategy,
      );
}

/// Import in flight — [done] of [total] units committed.
final class ImportWizardImporting extends ImportWizardState {
  const ImportWizardImporting({required this.done, required this.total});

  final int done;
  final int total;

  double get progress => total == 0 ? 0 : done / total;
}

/// Import finished.
final class ImportWizardSuccess extends ImportWizardState {
  const ImportWizardSuccess({
    required this.createdCount,
    required this.updatedCount,
    required this.skippedCount,
  });

  final int createdCount;
  final int updatedCount;
  final int skippedCount;
}

/// The whole flow failed (unsupported file, parse error, or a network /
/// crypto failure while committing).
final class ImportWizardFailure extends ImportWizardState {
  const ImportWizardFailure(this.reason);

  final ImportFailureReason reason;
}

/// Why an import could not complete.
enum ImportFailureReason {
  emptyFile,
  encryptedFile,
  unrecognisedFile,
  noEntries,
  crypto,
  network,
  unknown,
}

extension ImportPreviewItemResolution on ImportPreviewItem {
  /// Whether this item will actually be imported, taking the global
  /// [strategy] into account: a conflicting item set to "skip" is
  /// excluded even if the user left it toggled on.
  bool effectiveIncluded(ImportConflictStrategy strategy) {
    if (!included) return false;
    if (hasConflict && strategy == ImportConflictStrategy.skip) return false;
    return true;
  }
}
