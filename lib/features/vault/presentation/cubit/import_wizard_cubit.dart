import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/import/import_engine.dart';
import '../../data/import/import_models.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/import_draft.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../../domain/repositories/entry_repository.dart';
import 'import_wizard_state.dart';

export 'import_wizard_state.dart';

/// Drives the multi-step import wizard for a single target vault.
///
/// Steps:
///   1. [parseBytes] — parse the picked file, detect its format, and
///      diff it against the vault's existing entries to flag conflicts.
///   2. (manual CSV only) [applyMapping] — re-parse with user-mapped
///      columns.
///   3. [import] — encrypt every included entry on-device (VK unwrapped
///      once in the repository) and commit in chunks, streaming progress.
///
/// Secrets flow through [ParsedEntry] payloads but never through logs.
class ImportWizardCubit extends Cubit<ImportWizardState> {
  ImportWizardCubit({
    required this.repository,
    required this.vaultId,
    AnalyticsService? analytics,
  })  : _analytics = analytics ?? AnalyticsService.instance,
        super(const ImportWizardInitial());

  final EntryRepository repository;
  final String vaultId;
  final AnalyticsService _analytics;

  /// Cached table for the manual-mapping step so [applyMapping] can
  /// re-parse without re-reading the file.
  CsvTable? _pendingTable;

  /// Existing entries keyed by trimmed, lower-cased label — the conflict
  /// index rebuilt on each parse.
  Map<String, EntryEntity> _existingByLabel = const {};

  /// Parses [bytes] (with an optional [fileName] hint), loads the vault's
  /// current entries, and moves to the preview or manual-mapping step.
  Future<void> parseBytes(Uint8List bytes, {String? fileName}) async {
    emit(const ImportWizardParsing());
    try {
      await _loadExistingEntries();
      final outcome = ImportEngine.parse(bytes, fileName: fileName);
      switch (outcome) {
        case ImportParsed(:final result):
          _emitPreview(result);
        case ImportNeedsMapping(:final table):
          _pendingTable = table;
          emit(ImportWizardNeedsMapping(table));
        case ImportUnsupported(:final reason):
          _trackFailed('unsupported');
          emit(ImportWizardFailure(_mapUnsupported(reason)));
      }
    } on EntryException catch (e) {
      _trackFailed(e.kind.name);
      emit(ImportWizardFailure(_mapEntryError(e.kind)));
    } catch (e, s) {
      AppLogger.e('Import', 'parse failed', error: e, stackTrace: s);
      _trackFailed('parse-error');
      emit(const ImportWizardFailure(ImportFailureReason.unrecognisedFile));
    }
  }

  /// Re-parses the pending CSV with a user-supplied [mapping].
  void applyMapping(ColumnMapping mapping) {
    final table = _pendingTable;
    if (table == null) return;
    final result = ImportEngine.parseWithMapping(table, mapping);
    _emitPreview(result);
  }

  /// Toggles whether the item at [index] is included in the import.
  void toggleItem(int index) {
    final current = state;
    if (current is! ImportWizardPreview) return;
    if (index < 0 || index >= current.items.length) return;
    final items = List<ImportPreviewItem>.from(current.items);
    items[index] = items[index].copyWith(included: !items[index].included);
    emit(current.copyWith(items: items));
  }

  /// Sets the global strategy for conflicting entries.
  void setConflictStrategy(ImportConflictStrategy strategy) {
    final current = state;
    if (current is! ImportWizardPreview) return;
    emit(current.copyWith(conflictStrategy: strategy));
  }

  /// Encrypts and commits the included entries. [privateKey] comes from
  /// the unlocked auth state; the caller owns zeroing its copy.
  Future<void> import({required Uint8List privateKey, String? wrappedVK}) async {
    final current = state;
    if (current is! ImportWizardPreview) return;
    if (privateKey.isEmpty) {
      emit(const ImportWizardFailure(ImportFailureReason.crypto));
      return;
    }

    final creates = <ImportEntryDraft>[];
    final overwrites = <ImportEntryOverwrite>[];
    final existingLabels = _existingByLabel.keys.toSet();

    for (final item in current.items) {
      if (!item.effectiveIncluded(current.conflictStrategy)) continue;
      final parsed = item.parsed;
      if (item.hasConflict &&
          current.conflictStrategy == ImportConflictStrategy.overwrite) {
        overwrites.add(ImportEntryOverwrite(
          entryId: item.conflict!.id,
          label: parsed.name,
          description: parsed.folder,
          type: EntryType.credential,
          payload: parsed.toPayload(),
          urlDomain: parsed.urlDomain,
          createdAt: item.conflict!.createdAt,
        ));
      } else {
        final label = item.hasConflict &&
                current.conflictStrategy == ImportConflictStrategy.rename
            ? _uniqueLabel(parsed.name, existingLabels)
            : parsed.name;
        existingLabels.add(label.trim().toLowerCase());
        creates.add(ImportEntryDraft(
          label: label,
          description: parsed.folder,
          type: EntryType.credential,
          payload: parsed.toPayload(),
          urlDomain: parsed.urlDomain,
        ));
      }
    }

    final total = creates.length + overwrites.length;
    if (total == 0) {
      emit(const ImportWizardFailure(ImportFailureReason.noEntries));
      return;
    }

    emit(ImportWizardImporting(done: 0, total: total));
    try {
      final result = await repository.importEntriesEncrypted(
        vaultId: vaultId,
        format: current.format.id,
        creates: creates,
        overwrites: overwrites,
        privateKey: privateKey,
        wrappedVK: wrappedVK,
        onProgress: (done, t) => emit(ImportWizardImporting(done: done, total: t)),
      );
      _analytics.capture('vault', 'import-wizard-completed', properties: {
        'count': result.total,
        'format': current.format.id,
        'skipped': current.skippedCount,
      });
      emit(ImportWizardSuccess(
        createdCount: result.createdCount,
        updatedCount: result.updatedCount,
        skippedCount: current.skippedCount,
      ));
    } on EntryException catch (e) {
      _trackFailed(e.kind.name);
      emit(ImportWizardFailure(_mapEntryError(e.kind)));
    } catch (e, s) {
      AppLogger.e('Import', 'import commit failed', error: e, stackTrace: s);
      _trackFailed('commit-error');
      emit(const ImportWizardFailure(ImportFailureReason.unknown));
    }
  }

  Future<void> _loadExistingEntries() async {
    final existing = await repository.listEntries(vaultId);
    _existingByLabel = {
      for (final e in existing) e.label.trim().toLowerCase(): e,
    };
  }

  void _emitPreview(ParsedFile result) {
    if (result.entries.isEmpty) {
      _trackFailed('no-entries');
      emit(const ImportWizardFailure(ImportFailureReason.noEntries));
      return;
    }
    final items = [
      for (final parsed in result.entries)
        ImportPreviewItem(
          parsed: parsed,
          conflict: _existingByLabel[parsed.name.trim().toLowerCase()],
        ),
    ];
    emit(ImportWizardPreview(
      format: result.format,
      items: items,
      skippedCount: result.skippedCount,
      conflictStrategy: ImportConflictStrategy.rename,
    ));
  }

  String _uniqueLabel(String base, Set<String> takenLower) {
    if (!takenLower.contains(base.trim().toLowerCase())) return base;
    var n = 2;
    while (takenLower.contains('$base ($n)'.trim().toLowerCase())) {
      n++;
    }
    return '$base ($n)';
  }

  void _trackFailed(String reason) {
    _analytics.capture('vault', 'import-failed', properties: {
      'format': state is ImportWizardPreview
          ? (state as ImportWizardPreview).format.id
          : 'unknown',
      'reason': reason,
    });
  }

  ImportFailureReason _mapUnsupported(ImportUnsupportedReason reason) =>
      switch (reason) {
        ImportUnsupportedReason.empty => ImportFailureReason.emptyFile,
        ImportUnsupportedReason.encrypted => ImportFailureReason.encryptedFile,
        ImportUnsupportedReason.unrecognised =>
          ImportFailureReason.unrecognisedFile,
      };

  ImportFailureReason _mapEntryError(EntryErrorKind kind) => switch (kind) {
        EntryErrorKind.networkError => ImportFailureReason.network,
        EntryErrorKind.cryptoFailure => ImportFailureReason.crypto,
        _ => ImportFailureReason.unknown,
      };
}
