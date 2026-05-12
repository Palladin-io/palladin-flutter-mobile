import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../../domain/repositories/entry_repository.dart';
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
  EditEntryCubit({required this.repository}) : super(const EditEntryInitial());

  final EntryRepository repository;

  /// Skips the reveal step — the caller already has the plaintext payload
  /// cached (e.g. from the reveal panel on the entries tab).
  void setReady(EntryEntity entry, Map<String, dynamic> payload) {
    emit(EditEntryReady(entry: entry, payload: payload));
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
      final revealed = await repository.revealEntry(
        vaultId: entry.vaultId,
        entryId: entry.id,
        privateKey: privateKey,
        wrappedVK: wrappedVK,
      );
      emit(EditEntryReady(entry: revealed.entry, payload: revealed.payload));
    } on EntryException catch (e) {
      AppLogger.w('Entry', 'revealForEdit failed: ${e.kind.name}');
      emit(EditEntryError(e.kind));
    } catch (e, s) {
      AppLogger.e('Entry', 'revealForEdit failed unexpectedly',
          error: e, stackTrace: s);
      emit(const EditEntryError(EntryErrorKind.unknown));
    }
  }

  /// Re-encrypts and saves the edited entry.
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
  }) async {
    if (label.trim().isEmpty || privateKey.isEmpty) {
      AppLogger.w('Entry', 'updateEntry called with invalid input');
      emit(const EditEntryError(EntryErrorKind.unknown));
      return;
    }

    AppLogger.d('Entry', 'Updating entry id=$entryId');
    emit(const EditEntryLoading());
    try {
      final updated = await repository.updateEntryEncrypted(
        vaultId: vaultId,
        entryId: entryId,
        label: label.trim(),
        description: _trimToNull(description),
        icon: _trimToNull(icon),
        type: type,
        payload: payload,
        urlDomain: _trimToNull(urlDomain),
        privateKey: privateKey,
        wrappedVK: wrappedVK,
      );
      AppLogger.i('Entry', 'Entry updated: id=${updated.id}');
      emit(EditEntrySuccess(updated));
    } on EntryException catch (e) {
      AppLogger.w('Entry', 'updateEntry failed: ${e.kind.name}');
      emit(EditEntryError(e.kind));
    } catch (e, s) {
      AppLogger.e('Entry', 'updateEntry failed unexpectedly',
          error: e, stackTrace: s);
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
      AppLogger.e('Entry', 'deleteEntry failed unexpectedly',
          error: e, stackTrace: s);
      emit(const EditEntryError(EntryErrorKind.unknown));
    }
  }

  String? _trimToNull(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
