import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../../core/crypto/vault_session_store.dart';
import '../services/member_sync_service.dart';
import '../../../autofill/data/autofill_mutation_notifier.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/import_draft.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../../domain/repositories/entry_repository.dart';
import '../datasources/entry_remote_datasource.dart';
import '../datasources/vault_remote_datasource.dart';
import '../models/create_entry_request.dart';
import '../models/entry_model.dart';
import '../models/import_entries_request.dart';
import '../models/update_entry_request.dart';
import '../services/entry_crypto_service.dart';
import '../services/canonical_import_projection_service.dart';
import '../services/canonical_entry_detail_service.dart';
import '../services/local_current_entry_service.dart';

/// Concrete implementation of [EntryRepository].
///
/// Responsibilities:
///   * Translates DioExceptions into typed [EntryException]s so the
///     presentation layer can render localized error messages.
///   * Owns the wrappedVK lifecycle — fetches it from the vault
///     datasource, hands it to [EntryCryptoService.unwrapVK] to derive
///     the VK, and zeroes the plaintext VK in `finally`.
///   * Never lets plaintext VK leak above the data layer.
class EntryRepositoryImpl implements EntryRepository {
  EntryRepositoryImpl({
    required this.entryDatasource,
    required this.vaultDatasource,
    required this.cryptoService,
    this.canonicalImport,
    this.autoFillMutationNotifier,
    this.localCurrentEntry,
    this.canonicalDetails,
    this.sessions,
    this.memberIndex,
  });

  final EntryRemoteDatasource entryDatasource;
  final VaultRemoteDatasource vaultDatasource;
  final EntryCryptoService cryptoService;
  final CanonicalImportProjectionService? canonicalImport;
  final AutoFillMutationNotifier? autoFillMutationNotifier;
  final LocalCurrentEntryService? localCurrentEntry;
  final CanonicalEntryDetailService? canonicalDetails;
  final VaultSessionStore? sessions;
  final MemberIndexReader? memberIndex;
  final Map<String, _CanonicalImportProgress> _canonicalImports = {};

  @override
  Future<List<EntryEntity>> listEntries(String vaultId) async {
    try {
      AppLogger.d('Entry', 'GET /api/vaults/$vaultId/entries');
      final models = await entryDatasource.listEntries(vaultId);
      for (final m in models) {
        AppLogger.d('Entry', 'entry ${m.id} icon=${m.icon}');
      }
      return models.map((m) => m.toEntity()).toList(growable: false);
    } on DioException catch (e, s) {
      AppLogger.e('Entry', 'listEntries failed', error: e, stackTrace: s);
      throw EntryException(_classifyError(e));
    }
  }

  Future<EntryEntity> _createEntry({
    required String vaultId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required String encryptedBlob,
    required String nonce,
    String? urlDomain,
    List<AgentField>? agentFields,
  }) async {
    try {
      AppLogger.d('Entry', 'POST /api/vaults/$vaultId/entries');
      final model = await entryDatasource.createEntry(
        vaultId,
        CreateEntryRequest(
          label: label,
          description: description,
          icon: icon,
          type: type.toWire(),
          content: EntryContentModel(
            encryptedBlob: encryptedBlob,
            nonce: nonce,
          ),
          deliveryPolicy: type.deliveryPolicyWire(),
          urlDomain: urlDomain,
          agentFields: agentFields,
        ),
      );
      await autoFillMutationNotifier?.notifyChanged();
      return model.toEntity();
    } on DioException catch (e, s) {
      AppLogger.e('Entry', 'createEntry failed', error: e, stackTrace: s);
      throw EntryException(_classifyError(e));
    }
  }

  @override
  Future<void> deleteEntry({
    required String vaultId,
    required String entryId,
  }) async {
    final canonical = canonicalDetails;
    final session = sessions;
    final index = memberIndex;
    if (canonical == null || session == null || index == null) {
      throw const EntryException(EntryErrorKind.cryptoFailure);
    }
    Uint8List? privateKey;
    try {
      final generation = session.memberKeySessionGeneration;
      privateKey = session.copyMemberPrivateKey();
      final matches = index
          .entries(vaultId)
          .where((entry) => entry.entryId == entryId);
      if (matches.length != 1 || matches.single.corrupt) {
        throw const EntryException(EntryErrorKind.cryptoFailure);
      }
      final entry = matches.single;
      await canonical.deleteEntry(
        expected: EntryEntity(
          id: entryId,
          vaultId: vaultId,
          label: entry.memberLabel,
          type: EntryTypeExtension.fromWire(entry.entryType),
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          currentRevision: entry.revision,
          currentKeyVersion: entry.currentKeyVersion,
          lifecycleState: entry.state,
        ),
        memberPrivateKey: privateKey,
        isSessionCurrent: () =>
            session.memberKeySessionGeneration == generation,
      );
    } on CanonicalEntryDetailException catch (error) {
      throw EntryException(switch (error.kind) {
        CanonicalEntryDetailError.conflict => EntryErrorKind.validation,
        CanonicalEntryDetailError.corrupt => EntryErrorKind.cryptoFailure,
        CanonicalEntryDetailError.forbidden => EntryErrorKind.forbidden,
        CanonicalEntryDetailError.notFound => EntryErrorKind.notFound,
        CanonicalEntryDetailError.network => EntryErrorKind.networkError,
      });
    } on StateError {
      throw const EntryException(EntryErrorKind.forbidden);
    } finally {
      privateKey?.fillRange(0, privateKey.length, 0);
    }
  }

  @override
  Future<RevealedEntry> revealEntry({
    required String vaultId,
    required String entryId,
    required Uint8List privateKey,
    String? wrappedVK,
  }) async {
    AppLogger.d('Entry', 'Revealing entry id=$entryId');
    final local = localCurrentEntry;
    if (local != null) {
      try {
        final snapshot = await local.revealCurrent(
          vaultId: vaultId,
          entryId: entryId,
          memberPrivateKey: privateKey,
        );
        try {
          final secret = snapshot.secret;
          final wireType = secret['entryType'];
          final label = secret['memberLabel'];
          final currentRevision = snapshot.entry['currentRevision'];
          final currentKeyVersion = snapshot.entry['currentKeyVersion'];
          if (wireType is! int ||
              label is! String ||
              currentRevision is! String ||
              currentKeyVersion is! int) {
            throw const EntryException(EntryErrorKind.cryptoFailure);
          }
          final payload = Map<String, dynamic>.from(snapshot.payload);
          final updatedAt = DateTime.tryParse(
            snapshot.entry['updatedAt'] as String? ?? '',
          );
          final entry = EntryEntity(
            id: entryId,
            vaultId: vaultId,
            label: label,
            description: secret['description'] as String?,
            icon: secret['iconReference'] as String?,
            type: EntryTypeExtension.fromWire(wireType),
            urlDomain: payload['urlDomain'] as String?,
            createdAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            currentRevision: currentRevision,
            currentKeyVersion: currentKeyVersion,
          );
          if (entry.type == EntryType.creditCard) {
            CreditCardPayload.fromJson(payload);
          }
          return RevealedEntry(entry: entry, payload: payload);
        } finally {
          snapshot.clear();
        }
      } on CanonicalEntryDetailException catch (error) {
        throw EntryException(switch (error.kind) {
          CanonicalEntryDetailError.conflict => EntryErrorKind.validation,
          CanonicalEntryDetailError.corrupt => EntryErrorKind.cryptoFailure,
          CanonicalEntryDetailError.forbidden => EntryErrorKind.forbidden,
          CanonicalEntryDetailError.notFound => EntryErrorKind.notFound,
          CanonicalEntryDetailError.network => EntryErrorKind.networkError,
        });
      }
    }
    final detail = await _fetchDetail(vaultId, entryId);
    // Prefer the wrappedVK threaded down from the vault detail load —
    // falling back to a fetch keeps the call resilient when callers
    // (tests, future flows) don't have it cached.
    final vk = wrappedVK ?? await _fetchWrappedVK(vaultId);

    Uint8List? vaultKey;
    try {
      vaultKey = await cryptoService.unwrapVK(
        wrappedVK: vk,
        privateKey: privateKey,
      );
      final payload = await cryptoService.decryptEntry(
        content: detail.content,
        vaultKey: vaultKey,
      );
      final entry = detail.summary.toEntity();
      if (entry.type == EntryType.creditCard) {
        CreditCardPayload.fromJson(payload);
      }
      return RevealedEntry(entry: entry, payload: payload);
    } finally {
      if (vaultKey != null) {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
    }
  }

  @override
  Future<EntryEntity> createEntryEncrypted({
    required String vaultId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? urlDomain,
    required Uint8List privateKey,
    String? wrappedVK,
    List<AgentField>? agentFields,
  }) async {
    AppLogger.d('Entry', 'Creating encrypted entry in vault $vaultId');
    // See [revealEntry] — same fallback contract.
    final vk = wrappedVK ?? await _fetchWrappedVK(vaultId);

    Uint8List? vaultKey;
    try {
      vaultKey = await cryptoService.unwrapVK(
        wrappedVK: vk,
        privateKey: privateKey,
      );
      final encrypted = await cryptoService.encryptEntry(
        payload: payload,
        vaultKey: vaultKey,
      );
      return await _createEntry(
        vaultId: vaultId,
        label: label,
        description: description,
        icon: icon,
        type: type,
        encryptedBlob: encrypted.encryptedBlob,
        nonce: encrypted.nonce,
        urlDomain: urlDomain,
        agentFields: agentFields,
      );
    } finally {
      if (vaultKey != null) {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
    }
  }

  @override
  Future<EntryEntity> updateEntryEncrypted({
    required String vaultId,
    required String entryId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? urlDomain,
    required Uint8List privateKey,
    String? wrappedVK,
    required DateTime createdAt,
    List<AgentField>? agentFields,
  }) async {
    AppLogger.d('Entry', 'Updating encrypted entry id=$entryId');
    final vk = wrappedVK ?? await _fetchWrappedVK(vaultId);

    Uint8List? vaultKey;
    try {
      vaultKey = await cryptoService.unwrapVK(
        wrappedVK: vk,
        privateKey: privateKey,
      );
      final encrypted = await cryptoService.encryptEntry(
        payload: payload,
        vaultKey: vaultKey,
      );
      try {
        await entryDatasource.updateEntry(
          vaultId,
          entryId,
          UpdateEntryRequest(
            label: label,
            description: description,
            icon: icon,
            type: type.toWire(),
            content: EntryContentModel(
              encryptedBlob: encrypted.encryptedBlob,
              nonce: encrypted.nonce,
            ),
            deliveryPolicy: type.deliveryPolicyWire(),
            urlDomain: urlDomain,
            agentFields: agentFields,
          ),
        );
        await autoFillMutationNotifier?.notifyChanged();
      } on DioException catch (e, s) {
        AppLogger.e('Entry', 'updateEntry failed', error: e, stackTrace: s);
        throw EntryException(_classifyError(e));
      }
      // Build entity locally — PUT returns 204 No Content. Preserve the
      // original [createdAt] (passed in by the caller) so editing an entry
      // does not overwrite its creation timestamp. `updatedAt` is set to
      // `now()` as a best-effort optimistic value — close enough for UI
      // ordering, and a subsequent list refresh will overwrite it with the
      // server-truthy value.
      return EntryEntity(
        id: entryId,
        vaultId: vaultId,
        label: label,
        description: description,
        icon: icon,
        type: type,
        urlDomain: urlDomain,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
    } finally {
      if (vaultKey != null) {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
    }
  }

  @override
  Future<ImportResult> importEntriesEncrypted({
    required String vaultId,
    required String format,
    required List<ImportEntryDraft> creates,
    required List<ImportEntryOverwrite> overwrites,
    required Uint8List privateKey,
    String? wrappedVK,
    int chunkSize = 50,
    void Function(int done, int total)? onProgress,
  }) async {
    final canonical = canonicalImport;
    if (canonical != null) {
      return _importCanonical(
        canonical: canonical,
        vaultId: vaultId,
        format: format,
        creates: creates,
        overwrites: overwrites,
        privateKey: privateKey,
        chunkSize: chunkSize.clamp(1, 50),
        onProgress: onProgress,
      );
    }
    AppLogger.d(
      'Entry',
      'Importing ${creates.length} new + ${overwrites.length} overwrites into $vaultId',
    );
    final vk = wrappedVK ?? await _fetchWrappedVK(vaultId);
    final total = creates.length + overwrites.length;
    var done = 0;
    AutoFillMutationLease? autoFillMutation;
    var remoteOutcomeAmbiguous = false;

    Future<void> beginAutoFillMutation() async {
      if (autoFillMutation != null) return;
      final notifier = autoFillMutationNotifier;
      if (notifier != null) {
        autoFillMutation = await notifier.beginMutation();
      }
    }

    Uint8List? vaultKey;
    try {
      vaultKey = await cryptoService.unwrapVK(
        wrappedVK: vk,
        privateKey: privateKey,
      );

      var createdCount = 0;
      // Chunk the bulk creates to the backend's per-request limit.
      for (var start = 0; start < creates.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, creates.length);
        final chunk = creates.sublist(start, end);
        final items = <ImportEntryItem>[];
        for (final draft in chunk) {
          final encrypted = await cryptoService.encryptEntry(
            payload: draft.payload,
            vaultKey: vaultKey,
          );
          items.add(
            ImportEntryItem(
              label: draft.label,
              description: draft.description,
              type: draft.type.toWire(),
              content: encrypted,
              deliveryPolicy: draft.type.deliveryPolicyWire(),
              urlDomain: draft.urlDomain,
              icon: draft.icon,
            ),
          );
        }
        await beginAutoFillMutation();
        remoteOutcomeAmbiguous = true;
        try {
          createdCount += await entryDatasource.importEntries(
            vaultId,
            ImportEntriesRequest(format: format, entries: items),
          );
          remoteOutcomeAmbiguous = false;
        } on DioException catch (e, s) {
          if (e.response != null) remoteOutcomeAmbiguous = false;
          AppLogger.e(
            'Entry',
            'importEntries chunk failed',
            error: e,
            stackTrace: s,
          );
          throw EntryException(_classifyError(e));
        }
        done += chunk.length;
        onProgress?.call(done, total);
      }

      var updatedCount = 0;
      for (final overwrite in overwrites) {
        final encrypted = await cryptoService.encryptEntry(
          payload: overwrite.payload,
          vaultKey: vaultKey,
        );
        await beginAutoFillMutation();
        remoteOutcomeAmbiguous = true;
        try {
          await entryDatasource.updateEntry(
            vaultId,
            overwrite.entryId,
            UpdateEntryRequest(
              label: overwrite.label,
              description: overwrite.description,
              type: overwrite.type.toWire(),
              content: encrypted,
              deliveryPolicy: overwrite.type.deliveryPolicyWire(),
              urlDomain: overwrite.urlDomain,
              icon: overwrite.icon,
            ),
          );
          remoteOutcomeAmbiguous = false;
          updatedCount++;
        } on DioException catch (e, s) {
          if (e.response != null) remoteOutcomeAmbiguous = false;
          AppLogger.e(
            'Entry',
            'import overwrite failed',
            error: e,
            stackTrace: s,
          );
          throw EntryException(_classifyError(e));
        }
        done++;
        onProgress?.call(done, total);
      }

      AppLogger.i(
        'Entry',
        'Import done: created=$createdCount updated=$updatedCount',
      );
      return ImportResult(
        createdCount: createdCount,
        updatedCount: updatedCount,
      );
    } finally {
      try {
        final mutation = autoFillMutation;
        if (mutation != null) {
          if (remoteOutcomeAmbiguous) {
            await mutation.leaveAmbiguous();
          } else {
            await mutation.complete();
          }
        }
      } finally {
        if (vaultKey != null) {
          vaultKey.fillRange(0, vaultKey.length, 0);
        }
      }
    }
  }

  Future<ImportResult> _importCanonical({
    required CanonicalImportProjectionService canonical,
    required String vaultId,
    required String format,
    required List<ImportEntryDraft> creates,
    required List<ImportEntryOverwrite> overwrites,
    required Uint8List privateKey,
    required int chunkSize,
    void Function(int done, int total)? onProgress,
  }) async {
    if (overwrites.isNotEmpty) {
      throw const EntryException(EntryErrorKind.validation);
    }
    var progress = _canonicalImports[vaultId];
    if (progress == null ||
        progress.format != format ||
        progress.total != creates.length) {
      progress = _CanonicalImportProgress(format, creates.length);
      _canonicalImports[vaultId] = progress;
    }
    var start = progress.committedRows;
    AutoFillMutationLease? autoFillMutation;
    var remoteOutcomeAmbiguous = false;

    Future<void> beginAutoFillMutation() async {
      if (autoFillMutation != null) return;
      final notifier = autoFillMutationNotifier;
      if (notifier != null) {
        autoFillMutation = await notifier.beginMutation();
      }
    }

    onProgress?.call(start, creates.length);
    try {
      while (start < creates.length) {
        final end = (start + chunkSize).clamp(0, creates.length);
        var pending = progress.pending;
        if (pending == null || pending.start != start || pending.end != end) {
          final ids = await entryDatasource.issueCreationChallenges(
            vaultId,
            count: end - start,
          );
          final payloads = await canonical.prepareCredentialBatch(
            vaultId: vaultId,
            entryIds: ids,
            drafts: creates.sublist(start, end),
            memberPrivateKey: privateKey,
          );
          pending = _PendingCanonicalBatch(start, end, payloads);
          progress.pending = pending;
        }
        final request = ImportEntriesRequest(
          format: format,
          entries: pending.entries,
        );
        await beginAutoFillMutation();
        remoteOutcomeAmbiguous = true;
        try {
          await entryDatasource.importEntries(vaultId, request);
          remoteOutcomeAmbiguous = false;
        } on DioException catch (error) {
          if (error.response != null) {
            remoteOutcomeAmbiguous = false;
            throw EntryException(_classifyError(error));
          }
          // Lost response: retry the exact same ids, nonces and ciphertext.
          try {
            await entryDatasource.importEntries(vaultId, request);
            remoteOutcomeAmbiguous = false;
          } on DioException catch (retryError) {
            if (retryError.response != null) remoteOutcomeAmbiguous = false;
            throw EntryException(_classifyError(retryError));
          }
        }
        progress.committedRows = end;
        progress.pending = null;
        start = end;
        onProgress?.call(start, creates.length);
      }
      _canonicalImports.remove(vaultId);
      return ImportResult(createdCount: creates.length, updatedCount: 0);
    } on CanonicalImportPreparationException catch (error) {
      AppLogger.e(
        'Entry',
        'Canonical import preparation failed at ${error.stage.name}'
            '${error.causeType == null ? '' : ' (${error.causeType})'}',
      );
      throw const EntryException(EntryErrorKind.cryptoFailure);
    } catch (_) {
      // Keep only the current unconfirmed ciphertext batch plus committed row
      // count. A retry resumes without rebuilding successful transitions.
      rethrow;
    } finally {
      final mutation = autoFillMutation;
      if (mutation != null) {
        if (remoteOutcomeAmbiguous) {
          await mutation.leaveAmbiguous();
        } else {
          await mutation.complete();
        }
      }
    }
  }

  @override
  Future<List<RevealedEntry>> revealAutoFillCredentials({
    required String vaultId,
    required Uint8List privateKey,
    String? wrappedVK,
  }) async {
    final summaries = await listEntries(vaultId);
    final candidates = summaries
        .where(
          (entry) =>
              entry.type == EntryType.credential &&
              (entry.urlDomain?.trim().isNotEmpty ?? false),
        )
        .toList(growable: false);
    if (candidates.isEmpty) return const [];

    final vk = wrappedVK ?? await _fetchWrappedVK(vaultId);
    Uint8List? vaultKey;
    try {
      vaultKey = await cryptoService.unwrapVK(
        wrappedVK: vk,
        privateKey: privateKey,
      );
      final revealed = <RevealedEntry>[];
      for (final summary in candidates) {
        final detail = await _fetchDetail(vaultId, summary.id);
        final payload = await cryptoService.decryptEntry(
          content: detail.content,
          vaultKey: vaultKey,
        );
        revealed.add(
          RevealedEntry(entry: detail.summary.toEntity(), payload: payload),
        );
      }
      return revealed;
    } finally {
      vaultKey?.fillRange(0, vaultKey.length, 0);
    }
  }

  /// Wraps the vault datasource's wrappedVK lookup with our typed error
  /// classifier so the entry-level cubit only ever sees [EntryException]s.
  Future<String> _fetchWrappedVK(String vaultId) async {
    try {
      return await vaultDatasource.getVaultWrappedKey(vaultId);
    } on DioException catch (e, s) {
      AppLogger.e('Entry', 'wrappedVK fetch failed', error: e, stackTrace: s);
      throw EntryException(_classifyError(e));
    }
  }

  Future<EntryDetailModel> _fetchDetail(String vaultId, String entryId) async {
    try {
      return await entryDatasource.getEntry(vaultId, entryId);
    } on DioException catch (e, s) {
      AppLogger.e('Entry', 'getEntry failed', error: e, stackTrace: s);
      throw EntryException(_classifyError(e));
    }
  }

  /// Maps a [DioException] to a typed [EntryErrorKind].
  EntryErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return EntryErrorKind.networkError;
    }

    final status = e.response?.statusCode;
    return switch (status) {
      404 => EntryErrorKind.notFound,
      403 => EntryErrorKind.forbidden,
      400 => EntryErrorKind.validation,
      _ => EntryErrorKind.unknown,
    };
  }
}

final class _CanonicalImportProgress {
  _CanonicalImportProgress(this.format, this.total);

  final String format;
  final int total;
  int committedRows = 0;
  _PendingCanonicalBatch? pending;
}

final class _PendingCanonicalBatch {
  const _PendingCanonicalBatch(this.start, this.end, this.entries);

  final int start;
  final int end;
  final List<Map<String, dynamic>> entries;
}
