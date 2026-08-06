import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../grants/domain/entities/grant.dart';
import '../../../grants/domain/exceptions/grants_exceptions.dart';
import '../../../grants/domain/repositories/grants_repository.dart';
import '../../../public_asset_catalog/domain/services/public_hostname.dart';
import '../../../public_asset_catalog/domain/entities/public_asset.dart';
import '../../../public_asset_catalog/domain/services/website_icon_service.dart';
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
    required this.grantsRepository,
    required this.vaultId,
    this.websiteIconService,
    AnalyticsService? analytics,
  }) : super(const ImportWizardInitial());

  final EntryRepository repository;
  final GrantsRepository grantsRepository;
  final String vaultId;
  final WebsiteIconService? websiteIconService;

  /// Backend field-length limits (import batch is atomic — one over-length
  /// field 400s the whole batch), so clamp defensively client-side.
  static const int _maxLabel = 200;
  static const int _maxDescription = 2000;
  static const int _maxUrlDomain = 255;
  static const Duration _iconWait = Duration(seconds: 15);

  /// Cached table for the manual-mapping step so [applyMapping] can
  /// re-parse without re-reading the file.
  CsvTable? _pendingTable;

  /// Existing entries keyed by trimmed, lower-cased label — the conflict
  /// index rebuilt on each parse.
  Map<String, EntryEntity> _existingByLabel = const {};
  int _sessionEpoch = 0;

  /// Parses [bytes] (with an optional [fileName] hint), loads the vault's
  /// current entries, and moves to the preview or manual-mapping step.
  Future<void> parseBytes(Uint8List bytes, {String? fileName}) async {
    final epoch = _sessionEpoch;
    emit(const ImportWizardParsing());
    try {
      // The backend requires per-entry re-wrap material for every active
      // FULL grant on the vault. The mobile create/import flow can't produce
      // it, so block up-front rather than fail the atomic batch server-side.
      if (await _hasActiveFullGrants()) {
        if (!_isCurrent(epoch)) return;
        _trackFailed('full-grants-blocked');
        emit(const ImportWizardFailure(ImportFailureReason.fullGrantsBlocked));
        return;
      }
      await _loadExistingEntries();
      if (!_isCurrent(epoch)) return;
      final outcome = ImportEngine.parse(bytes, fileName: fileName);
      if (!_isCurrent(epoch)) return;
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
    } on GrantsException catch (e) {
      if (!_isCurrent(epoch)) return;
      // Grant lookup runs before we touch the file, so a wire failure here
      // must not be reported as an unrecognised file.
      _trackFailed(e.kind.name);
      emit(
        ImportWizardFailure(
          e.kind == GrantsErrorKind.networkError
              ? ImportFailureReason.network
              : ImportFailureReason.unknown,
        ),
      );
    } on EntryException catch (e) {
      if (!_isCurrent(epoch)) return;
      _trackFailed(e.kind.name);
      _clearPlaintextCaches();
      emit(ImportWizardFailure(_mapEntryError(e.kind)));
    } catch (_) {
      if (!_isCurrent(epoch)) return;
      AppLogger.e('Import', 'Import parse failed');
      _trackFailed('parse-error');
      emit(const ImportWizardFailure(ImportFailureReason.unrecognisedFile));
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Re-parses the pending CSV with a user-supplied [mapping].
  void applyMapping(ColumnMapping mapping) {
    final table = _pendingTable;
    if (table == null) return;
    final result = ImportEngine.parseWithMapping(table, mapping);
    _pendingTable = null;
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
  /// the unlocked auth state; the caller owns zeroing its copy. [untitledLabel]
  /// is the localized fallback used for entries the source left unnamed.
  Future<void> import({
    required Uint8List privateKey,
    required String untitledLabel,
    String? wrappedVK,
  }) async {
    final epoch = _sessionEpoch;
    final current = state;
    if (current is! ImportWizardPreview) return;
    if (privateKey.isEmpty) {
      emit(const ImportWizardFailure(ImportFailureReason.crypto));
      return;
    }

    final selected = current.items
        .where((item) => item.effectiveIncluded(current.conflictStrategy))
        .toList(growable: false);
    if (selected.isEmpty) {
      emit(const ImportWizardFailure(ImportFailureReason.noEntries));
      return;
    }
    // Enter a non-interactive state before the optional network reservation,
    // so a second tap cannot start another import with the same plaintext.
    final iconTotal = PublicHostname.unique(
      selected.map((item) => item.parsed.urlDomain),
      limit: 10000,
    ).length;
    _emitImportProgress(
      done: 0,
      total: websiteIconService != null && iconTotal > 0
          ? iconTotal
          : selected.length,
      phase: websiteIconService != null && iconTotal > 0
          ? ImportProgressPhase.icons
          : ImportProgressPhase.entries,
    );

    final creates = <ImportEntryDraft>[];
    final overwrites = <ImportEntryOverwrite>[];
    final existingLabels = _existingByLabel.keys.toSet();
    // Two source rows can collide with the same existing entry — only the
    // first may overwrite it, or the batch issues two PUTs to one entryId.
    final overwrittenIds = <String>{};
    final iconDomains = selected.map((item) => item.parsed.urlDomain);
    final publicAssets = websiteIconService != null && iconTotal > 0
        ? await websiteIconService!.ensureBatchWithin(
            iconDomains,
            timeout: _iconWait,
            onProgress: (ready, total) {
              if (_isCurrent(epoch)) {
                _emitImportProgress(
                  done: ready,
                  total: total,
                  phase: ImportProgressPhase.icons,
                );
              }
            },
          )
        : const <String, PublicAsset>{};
    if (!_isCurrent(epoch)) return;
    for (final item in current.items) {
      if (!item.effectiveIncluded(current.conflictStrategy)) continue;
      final parsed = item.parsed;
      final baseName = parsed.name ?? untitledLabel;
      if (item.hasConflict &&
          current.conflictStrategy == ImportConflictStrategy.overwrite) {
        if (!overwrittenIds.add(item.conflict!.id)) continue;
        overwrites.add(
          ImportEntryOverwrite(
            entryId: item.conflict!.id,
            label: _clamp(baseName, _maxLabel),
            description: _clampOrNull(parsed.folder, _maxDescription),
            type: EntryType.credential,
            payload: parsed.toPayload(),
            urlDomain: _clampOrNull(parsed.urlDomain, _maxUrlDomain),
            createdAt: item.conflict!.createdAt,
            icon: _iconReference(parsed.urlDomain, publicAssets),
          ),
        );
      } else {
        // Under the rename strategy, dedup both against the vault's existing
        // labels and against earlier rows in this same batch (two identical
        // names in the source file would otherwise collide).
        final collidesInBatch = existingLabels.contains(
          baseName.trim().toLowerCase(),
        );
        final label =
            current.conflictStrategy == ImportConflictStrategy.rename &&
                (item.hasConflict || collidesInBatch)
            ? _uniqueLabel(baseName, existingLabels)
            : baseName;
        existingLabels.add(label.trim().toLowerCase());
        creates.add(
          ImportEntryDraft(
            label: _clamp(label, _maxLabel),
            description: _clampOrNull(parsed.folder, _maxDescription),
            type: EntryType.credential,
            payload: parsed.toPayload(),
            urlDomain: _clampOrNull(parsed.urlDomain, _maxUrlDomain),
            icon: _iconReference(parsed.urlDomain, publicAssets),
          ),
        );
      }
    }

    final total = creates.length + overwrites.length;
    if (total == 0) {
      emit(const ImportWizardFailure(ImportFailureReason.noEntries));
      return;
    }

    _emitImportProgress(
      done: 0,
      total: total,
      phase: ImportProgressPhase.entries,
    );
    try {
      final result = await repository.importEntriesEncrypted(
        vaultId: vaultId,
        format: current.format.id,
        creates: creates,
        overwrites: overwrites,
        privateKey: privateKey,
        wrappedVK: wrappedVK,
        onProgress: (done, t) {
          if (_isCurrent(epoch)) {
            _emitImportProgress(
              done: done,
              total: t,
              phase: ImportProgressPhase.entries,
            );
          }
        },
      );
      if (!_isCurrent(epoch)) return;
      _clearPlaintextCaches();
      emit(
        ImportWizardSuccess(
          createdCount: result.createdCount,
          updatedCount: result.updatedCount,
          skippedCount: current.skippedCount,
        ),
      );
    } on EntryException catch (e) {
      if (!_isCurrent(epoch)) return;
      _trackFailed(e.kind.name);
      _clearPlaintextCaches();
      emit(ImportWizardFailure(_mapEntryError(e.kind)));
    } catch (_) {
      if (!_isCurrent(epoch)) return;
      AppLogger.e('Import', 'Import commit failed');
      _trackFailed('commit-error');
      _clearPlaintextCaches();
      emit(const ImportWizardFailure(ImportFailureReason.unknown));
    }
  }

  static String? _iconReference(
    String? domain,
    Map<String, PublicAsset> publicAssets,
  ) {
    final normalized = PublicHostname.normalize(domain);
    return normalized == null ? null : publicAssets[normalized]?.reference;
  }

  void _emitImportProgress({
    required int done,
    required int total,
    required ImportProgressPhase phase,
  }) {
    final current = state;
    if (current is ImportWizardImporting &&
        current.done == done &&
        current.total == total &&
        current.phase == phase) {
      return;
    }
    emit(ImportWizardImporting(done: done, total: total, phase: phase));
  }

  /// Pages through the vault's active grants looking for any FULL-scope
  /// grant. Bounded in practice (active grants per vault are few); the loop
  /// guards against a FULL grant sitting past the first page.
  Future<bool> _hasActiveFullGrants() async {
    final seenCursors = <String>{};
    String? cursor;
    do {
      final page = await grantsRepository.listGrants(
        vaultId,
        status: 'active',
        cursor: cursor,
        pageSize: 50,
      );
      if (page.grants.any((g) => g.scope == GrantScope.full)) return true;
      cursor = page.nextCursor;
      // Stop if the backend ever repeats a cursor (broken pagination) so we
      // can't spin forever.
      if (cursor != null && !seenCursors.add(cursor)) break;
    } while (cursor != null);
    return false;
  }

  static String _clamp(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  static String? _clampOrNull(String? value, int max) =>
      value == null ? null : _clamp(value, max);

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
          conflict: _existingByLabel[parsed.name?.trim().toLowerCase()],
        ),
    ];
    emit(
      ImportWizardPreview(
        format: result.format,
        items: items,
        skippedCount: result.skippedCount,
        conflictStrategy: ImportConflictStrategy.rename,
      ),
    );
  }

  String _uniqueLabel(String base, Set<String> takenLower) {
    // Leave room for the " (n)" suffix within the label limit, otherwise the
    // later clamp would cut the suffix off and re-introduce the duplicate.
    const suffixRoom = 8;
    final safeBase = _clamp(base, _maxLabel - suffixRoom);
    if (!takenLower.contains(base.trim().toLowerCase())) return base;
    var n = 2;
    while (takenLower.contains('$safeBase ($n)'.trim().toLowerCase())) {
      n++;
    }
    return '$safeBase ($n)';
  }

  void _trackFailed(String reason) {
    // Import business events are recorded by the backend after commit. Mobile
    // intentionally emits no duplicate analytics and never serializes source
    // format or parser details from a plaintext import session.
  }

  void clearSensitiveState() {
    _sessionEpoch++;
    _clearPlaintextCaches();
    if (!isClosed) emit(const ImportWizardInitial());
  }

  void _clearPlaintextCaches() {
    _pendingTable = null;
    _existingByLabel = const {};
  }

  bool _isCurrent(int epoch) => !isClosed && epoch == _sessionEpoch;

  @override
  Future<void> close() {
    _sessionEpoch++;
    _clearPlaintextCaches();
    return super.close();
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
