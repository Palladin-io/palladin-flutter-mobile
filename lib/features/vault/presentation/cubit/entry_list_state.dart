import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';

/// Base class for all states of the entry list (Entries tab).
sealed class EntryListState {
  const EntryListState();
}

/// Idle — nothing has been requested yet.
final class EntryListInitial extends EntryListState {
  const EntryListInitial();
}

/// A request is in flight — fetching the list, deleting an entry, or
/// revealing one.
final class EntryListLoading extends EntryListState {
  const EntryListLoading();
}

/// Fetch succeeded. [entries] is the canonical list to render.
///
/// [revealedEntries] maps `entryId → decrypted payload` for entries the
/// user has expanded. Decryption is lazy (one fetch + decrypt per
/// reveal) and the map is rebuilt on every refresh so revealed
/// plaintext does not survive a list reload.
///
/// [transientErrorKind] carries the most recent per-row failure (e.g.
/// a reveal/delete that failed) WITHOUT replacing the loaded list with
/// a full-page error view. Pair it with [transientErrorTick] which
/// monotonically increases on every error emission so [BlocListener]
/// can distinguish repeated failures and surface them as a snackbar.
final class EntryListLoaded extends EntryListState {
  const EntryListLoaded(
    this.entries, {
    this.revealedEntries = const {},
    this.transientErrorKind,
    this.transientErrorTick = 0,
  });

  final List<EntryEntity> entries;
  final Map<String, Map<String, dynamic>> revealedEntries;

  /// The most recent transient operation error (reveal, delete, …).
  /// Null when nothing has failed since the last successful load.
  final EntryErrorKind? transientErrorKind;

  /// Monotonic counter incremented on every transient error emission.
  /// Lets BlocListener distinguish back-to-back failures of the same kind.
  final int transientErrorTick;

  /// Sentinel used by [copyWith] to distinguish "field omitted" from
  /// "explicitly clear this field". `transientErrorKind` is nullable, so
  /// plain `null` cannot signal "wipe me" without losing the difference
  /// between the two intents.
  static const Object _unset = Object();

  EntryListLoaded copyWith({
    List<EntryEntity>? entries,
    Map<String, Map<String, dynamic>>? revealedEntries,
    Object? transientErrorKind = _unset,
    int? transientErrorTick,
  }) {
    return EntryListLoaded(
      entries ?? this.entries,
      revealedEntries: revealedEntries ?? this.revealedEntries,
      transientErrorKind: identical(transientErrorKind, _unset)
          ? this.transientErrorKind
          : transientErrorKind as EntryErrorKind?,
      transientErrorTick: transientErrorTick ?? this.transientErrorTick,
    );
  }
}

/// The most recent operation failed. [kind] is a typed error so the UI
/// can render the correct localized message.
final class EntryListError extends EntryListState {
  const EntryListError(this.kind);

  final EntryErrorKind kind;
}
