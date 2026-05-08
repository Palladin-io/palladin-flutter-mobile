import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';

/// Base class for all states of the Add Entry screen.
sealed class CreateEntryState {
  const CreateEntryState();
}

/// Idle — form is open but the user hasn't submitted yet.
final class CreateEntryInitial extends CreateEntryState {
  const CreateEntryInitial();
}

/// A create request is in flight (crypto + network).
final class CreateEntryLoading extends CreateEntryState {
  const CreateEntryLoading();
}

/// The entry was successfully created. [entry] is the fresh metadata
/// returned by the backend — useful so the parent list can insert it
/// without re-fetching.
final class CreateEntrySuccess extends CreateEntryState {
  const CreateEntrySuccess(this.entry);

  final EntryEntity entry;
}

/// Creation failed. [kind] is a typed error so the UI can render the
/// correct localized message.
final class CreateEntryError extends CreateEntryState {
  const CreateEntryError(this.kind);

  final EntryErrorKind kind;
}
