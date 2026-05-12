import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';

sealed class EditEntryState {
  const EditEntryState();
}

final class EditEntryInitial extends EditEntryState {
  const EditEntryInitial();
}

/// Decrypting the existing payload to pre-populate form fields.
final class EditEntryRevealing extends EditEntryState {
  const EditEntryRevealing();
}

/// Payload decrypted — form is ready for editing.
final class EditEntryReady extends EditEntryState {
  const EditEntryReady({required this.entry, required this.payload});

  final EntryEntity entry;
  final Map<String, dynamic> payload;
}

/// Save request is in flight (crypto + network).
final class EditEntryLoading extends EditEntryState {
  const EditEntryLoading();
}

/// Entry saved successfully.
final class EditEntrySuccess extends EditEntryState {
  const EditEntrySuccess(this.entry);

  final EntryEntity entry;
}

/// Operation failed. [kind] drives the localized error message.
final class EditEntryError extends EditEntryState {
  const EditEntryError(this.kind);

  final EntryErrorKind kind;
}
