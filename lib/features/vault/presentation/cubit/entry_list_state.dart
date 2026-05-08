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
final class EntryListLoaded extends EntryListState {
  const EntryListLoaded(this.entries, {this.revealedEntries = const {}});

  final List<EntryEntity> entries;
  final Map<String, Map<String, dynamic>> revealedEntries;

  EntryListLoaded copyWith({
    List<EntryEntity>? entries,
    Map<String, Map<String, dynamic>>? revealedEntries,
  }) {
    return EntryListLoaded(
      entries ?? this.entries,
      revealedEntries: revealedEntries ?? this.revealedEntries,
    );
  }
}

/// The most recent operation failed. [kind] is a typed error so the UI
/// can render the correct localized message.
final class EntryListError extends EntryListState {
  const EntryListError(this.kind);

  final EntryErrorKind kind;
}
