import 'entry_entity.dart';

/// A new entry to create during an import — plaintext payload not yet
/// encrypted. The payload map holds secrets and must never be logged.
class ImportEntryDraft {
  const ImportEntryDraft({
    required this.label,
    this.description,
    required this.type,
    required this.payload,
    this.urlDomain,
  });

  final String label;
  final String? description;
  final EntryType type;
  final Map<String, dynamic> payload;
  final String? urlDomain;
}

/// An existing entry to overwrite during an import (conflict resolved as
/// "overwrite"). Carries the target [entryId] and original [createdAt] so
/// the update preserves the creation timestamp.
class ImportEntryOverwrite {
  const ImportEntryOverwrite({
    required this.entryId,
    required this.label,
    this.description,
    required this.type,
    required this.payload,
    this.urlDomain,
    required this.createdAt,
  });

  final String entryId;
  final String label;
  final String? description;
  final EntryType type;
  final Map<String, dynamic> payload;
  final String? urlDomain;
  final DateTime createdAt;
}

/// Summary of a completed import.
class ImportResult {
  const ImportResult({required this.createdCount, required this.updatedCount});

  final int createdCount;
  final int updatedCount;

  int get total => createdCount + updatedCount;
}
