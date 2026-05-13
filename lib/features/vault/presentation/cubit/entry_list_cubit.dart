import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../../domain/repositories/entry_repository.dart';
import 'entry_list_state.dart';

export 'entry_list_state.dart';

/// Drives the Entries tab on the vault detail screen.
///
/// Operations exposed:
///   * [loadEntries]   — fetches the canonical list from the backend.
///   * [revealEntry]   — fetches the encrypted blob for an entry, unwraps
///                       the VK on-device, decrypts the payload, and
///                       stashes it on the [EntryListLoaded] state.
///   * [hideEntry]     — drops a previously-revealed payload from state
///                       so the plaintext does not linger longer than
///                       the user wants.
///   * [deleteEntry]   — deletes an entry by id and refreshes the list.
///
/// All errors surface as [EntryListError] carrying a typed
/// [EntryErrorKind]. The plaintext VK never lives on the cubit's state —
/// it stays inside the repository call boundary.
class EntryListCubit extends Cubit<EntryListState> {
  EntryListCubit({
    required this.repository,
    required this.vaultId,
    String? wrappedVK,
  })  : _wrappedVK = wrappedVK,
        super(const EntryListInitial());

  final EntryRepository repository;
  final String vaultId;

  /// Cached base64 sealed VK threaded down from the vault detail load.
  ///
  /// When present, [revealEntry] passes it to the repository so we
  /// avoid a redundant `GET /api/vaults/{id}` round-trip. The value is
  /// not final — the vault detail cubit may finish loading after the
  /// entry list cubit is created (race on first open), in which case
  /// the page wires it in via [updateWrappedVK].
  String? _wrappedVK;
  String? get wrappedVK => _wrappedVK;

  /// Stores the base64 sealed VK so subsequent [revealEntry] calls
  /// can skip the extra vault fetch. Called from the page once the
  /// vault detail cubit emits [VaultDetailLoaded].
  void updateWrappedVK(String? vk) {
    _wrappedVK = vk;
  }

  Future<void> loadEntries() async {
    AppLogger.d('Entry', 'Loading entries for vault $vaultId');
    emit(const EntryListLoading());
    try {
      final entries = await repository.listEntries(vaultId);
      AppLogger.i('Entry', 'Loaded ${entries.length} entries');
      emit(EntryListLoaded(entries));
    } on EntryException catch (e) {
      AppLogger.w('Entry', 'Entry list load failed: ${e.kind.name}');
      emit(EntryListError(e.kind));
    } catch (e, s) {
      AppLogger.e('Entry', 'Entry list load failed unexpectedly',
          error: e, stackTrace: s);
      emit(const EntryListError(EntryErrorKind.unknown));
    }
  }

  /// Reveals a single entry by fetching its encrypted blob and
  /// decrypting it on-device. The plaintext payload is stored on the
  /// [EntryListLoaded] state under the entry id so the UI can render
  /// the reveal panel without re-fetching on every rebuild.
  ///
  /// [privateKey] must come from the unlocked auth state. The cubit
  /// never holds it — it is forwarded to the repository for the
  /// duration of the call.
  Future<void> revealEntry({
    required String entryId,
    required Uint8List privateKey,
  }) async {
    final current = state;
    if (current is! EntryListLoaded) {
      AppLogger.w('Entry', 'revealEntry called before loaded state');
      return;
    }
    if (current.revealedEntries.containsKey(entryId)) {
      // Already revealed — no need to refetch.
      return;
    }
    try {
      final revealed = await repository.revealEntry(
        vaultId: vaultId,
        entryId: entryId,
        privateKey: privateKey,
        wrappedVK: _wrappedVK,
      );
      // Refresh state in case it changed during the await.
      final newState = state;
      if (newState is! EntryListLoaded) return;
      final next = Map<String, Map<String, dynamic>>.from(
        newState.revealedEntries,
      )..[entryId] = revealed.payload;
      emit(newState.copyWith(revealedEntries: next));
    } on EntryException catch (e) {
      AppLogger.w('Entry', 'revealEntry failed: ${e.kind.name}');
      emit(EntryListError(e.kind));
    } catch (e, s) {
      AppLogger.e('Entry', 'revealEntry failed unexpectedly',
          error: e, stackTrace: s);
      emit(const EntryListError(EntryErrorKind.unknown));
    }
  }

  /// Drops a previously-revealed payload from state. UI should call
  /// this when the user collapses the reveal panel so the plaintext
  /// payload doesn't outlive the user's intent.
  void hideEntry(String entryId) {
    final current = state;
    if (current is! EntryListLoaded) return;
    if (!current.revealedEntries.containsKey(entryId)) return;
    final next = Map<String, Map<String, dynamic>>.from(
      current.revealedEntries,
    )..remove(entryId);
    emit(current.copyWith(revealedEntries: next));
  }

  Future<void> deleteEntry(String entryId) async {
    AppLogger.d('Entry', 'Deleting entry id=$entryId');
    try {
      await repository.deleteEntry(vaultId: vaultId, entryId: entryId);
      AppLogger.i('Entry', 'Entry deleted, refreshing list');
      await loadEntries();
    } on EntryException catch (e) {
      AppLogger.w('Entry', 'Delete failed: ${e.kind.name}');
      emit(EntryListError(e.kind));
    } catch (e, s) {
      AppLogger.e('Entry', 'Delete failed unexpectedly',
          error: e, stackTrace: s);
      emit(const EntryListError(EntryErrorKind.unknown));
    }
  }

  /// Inserts an entry that was just created via [CreateEntryCubit] into
  /// the loaded state without re-fetching the whole list. Falls back to
  /// a full reload if the cubit is not currently in the loaded state.
  Future<void> appendEntry(EntryEntity entry) async {
    AppLogger.d('Entry', 'appendEntry id=${entry.id} icon=${entry.icon}');
    final current = state;
    if (current is! EntryListLoaded) {
      await loadEntries();
      return;
    }
    emit(current.copyWith(entries: [entry, ...current.entries]));
  }

  /// Removes the entry with [entryId] from local state without making an
  /// API call — use when the API delete already succeeded in another cubit.
  void removeEntry(String entryId) {
    final current = state;
    if (current is! EntryListLoaded) return;
    final newList = current.entries.where((e) => e.id != entryId).toList();
    final newRevealed = Map<String, Map<String, dynamic>>.from(
      current.revealedEntries,
    )..remove(entryId);
    emit(current.copyWith(entries: newList, revealedEntries: newRevealed));
  }

  /// Replaces the entry matching [updated.id] in the loaded state after
  /// an edit. No-ops if the cubit is not in [EntryListLoaded] or if the
  /// entry is not found. The reveal payload for the edited entry is
  /// dropped so the next expand re-decrypts the fresh ciphertext.
  void replaceEntry(EntryEntity updated) {
    final current = state;
    if (current is! EntryListLoaded) return;
    final idx = current.entries.indexWhere((e) => e.id == updated.id);
    if (idx == -1) return;
    final newList = List<EntryEntity>.from(current.entries)..[idx] = updated;
    final newRevealed = Map<String, Map<String, dynamic>>.from(
      current.revealedEntries,
    )..remove(updated.id);
    emit(current.copyWith(entries: newList, revealedEntries: newRevealed));
  }
}
