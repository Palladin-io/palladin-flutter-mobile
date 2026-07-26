import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../../domain/repositories/entry_repository.dart';
import '../../data/services/canonical_entry_detail_service.dart';
import 'edit_entry_state.dart';

export 'edit_entry_state.dart';

/// Drives the Edit Entry page.
///
/// Lifecycle:
///   1. [revealForEdit] — fetches and decrypts the existing payload so
///      the form can be pre-populated. Emits [EditEntryReady] when done.
///   2. [updateEntry]  — re-encrypts the edited payload and PUTs the
///      update. Emits [EditEntrySuccess] with the updated entity.
///
/// Callers that already hold the decrypted payload (from
/// [EntryListCubit.revealedEntries]) should call [setReady] instead of
/// [revealForEdit] to skip the redundant network+crypto round-trip.
class EditEntryCubit extends Cubit<EditEntryState> {
  EditEntryCubit({required this.repository, required this.canonicalService})
    : super(const EditEntryInitial());

  final EntryRepository repository;
  final CanonicalEntryDetailService canonicalService;
  CanonicalEntrySnapshot? _snapshot;

  /// Whether another save can safely reuse the authenticated base revision.
  bool get hasCanonicalSnapshot => _snapshot != null;

  /// Skips the reveal step — the caller already has the plaintext payload
  /// cached (e.g. from the reveal panel on the entries tab).
  /// Surfaces a cryptoFailure error when the page is opened without a
  /// usable private key (vault locked / auth state out of sync). Without
  /// this the details tab would stay stuck on the reveal spinner forever.
  void markRevealUnavailable() {
    emit(const EditEntryError(EntryErrorKind.cryptoFailure));
  }

  /// Drops every reference to decrypted canonical state on lock/background.
  void clearSensitiveState() {
    final snapshot = _snapshot;
    snapshot?.payload.clear();
    snapshot?.secret.clear();
    snapshot?.entry.clear();
    _snapshot = null;
    emit(const EditEntryInitial());
  }

  /// Decrypts the entry payload so form fields can be pre-populated.
  Future<void> revealForEdit({
    required EntryEntity entry,
    required Uint8List privateKey,
    String? wrappedVK,
  }) async {
    AppLogger.d('Entry', 'Revealing entry id=${entry.id} for edit');
    emit(const EditEntryRevealing());
    try {
      final snapshot = await canonicalService.reveal(
        expected: entry,
        memberPrivateKey: privateKey,
      );
      _snapshot = snapshot;
      emit(EditEntryReady(entry: entry, payload: snapshot.payload));
    } on EntryException catch (e) {
      AppLogger.w('Entry', 'revealForEdit failed: ${e.kind.name}');
      emit(EditEntryError(e.kind));
    } on CanonicalEntryDetailException catch (e) {
      emit(
        EditEntryError(switch (e.kind) {
          CanonicalEntryDetailError.conflict => EntryErrorKind.validation,
          CanonicalEntryDetailError.corrupt => EntryErrorKind.cryptoFailure,
          CanonicalEntryDetailError.forbidden => EntryErrorKind.forbidden,
          CanonicalEntryDetailError.notFound => EntryErrorKind.notFound,
          CanonicalEntryDetailError.network => EntryErrorKind.networkError,
        }),
      );
    } catch (e, s) {
      AppLogger.e(
        'Entry',
        'revealForEdit failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(const EditEntryError(EntryErrorKind.unknown));
    }
  }

  /// Re-encrypts and saves the edited entry.
  ///
  /// [createdAt] must be the entry's original creation timestamp —
  /// callers should pass `entry.createdAt`. Without this the repository
  /// would default to `DateTime.now()` and overwrite the real creation
  /// time on every edit (PUT returns 204, so the server timestamp is
  /// not echoed back).
  Future<void> updateEntry({
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
    if (label.trim().isEmpty || privateKey.isEmpty) {
      AppLogger.w('Entry', 'updateEntry called with invalid input');
      emit(const EditEntryError(EntryErrorKind.unknown));
      return;
    }

    AppLogger.d('Entry', 'Updating entry id=$entryId');
    emit(const EditEntryLoading());
    try {
      final snapshot = _snapshot;
      if (snapshot == null) {
        emit(const EditEntryError(EntryErrorKind.cryptoFailure));
        return;
      }
      final updated = await canonicalService.update(
        snapshot: snapshot,
        expected: EntryEntity(
          id: entryId,
          vaultId: vaultId,
          label: label.trim(),
          type: type,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        label: label.trim(),
        description: _trimToNull(description) ?? '',
        icon: _trimToNull(icon) ?? '',
        type: type,
        content: payload,
        memberPrivateKey: privateKey,
      );
      AppLogger.i('Entry', 'Entry updated: id=${updated.id}');
      // The backend switched to N+1. Never let a second edit reuse N as its
      // optimistic base; the next edit must reveal the new canonical head.
      _snapshot = null;
      emit(EditEntrySuccess(updated));
    } on EntryException catch (e) {
      AppLogger.w('Entry', 'updateEntry failed: ${e.kind.name}');
      emit(EditEntryError(e.kind));
    } on CanonicalEntryDetailException catch (e) {
      if (e.kind == CanonicalEntryDetailError.conflict) {
        emit(const EditEntryConflict());
      } else {
        emit(
          EditEntryError(switch (e.kind) {
            CanonicalEntryDetailError.conflict => EntryErrorKind.validation,
            CanonicalEntryDetailError.corrupt => EntryErrorKind.cryptoFailure,
            CanonicalEntryDetailError.forbidden => EntryErrorKind.forbidden,
            CanonicalEntryDetailError.notFound => EntryErrorKind.notFound,
            CanonicalEntryDetailError.network => EntryErrorKind.networkError,
          }),
        );
      }
    } catch (e, s) {
      AppLogger.e(
        'Entry',
        'updateEntry failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(const EditEntryError(EntryErrorKind.unknown));
    }
  }

  /// Permanently deletes the entry. Emits [EditEntryDeleted] on success.
  Future<void> deleteEntry({
    required String vaultId,
    required String entryId,
  }) async {
    AppLogger.d('Entry', 'Deleting entry id=$entryId');
    emit(const EditEntryLoading());
    try {
      await repository.deleteEntry(vaultId: vaultId, entryId: entryId);
      AppLogger.i('Entry', 'Entry deleted: id=$entryId');
      emit(EditEntryDeleted(entryId));
    } on EntryException catch (e) {
      AppLogger.w('Entry', 'deleteEntry failed: ${e.kind.name}');
      emit(EditEntryError(e.kind));
    } catch (e, s) {
      AppLogger.e(
        'Entry',
        'deleteEntry failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(const EditEntryError(EntryErrorKind.unknown));
    }
  }

  String? _trimToNull(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<void> close() {
    _snapshot = null;
    return super.close();
  }
}
