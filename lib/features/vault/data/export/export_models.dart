/// Export file format selected by the user.
enum ExportFormat {
  csv('csv', 'text/csv'),
  json('json', 'application/json');

  const ExportFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

/// Explicit scope of a local plaintext export.
final class ExportOptions {
  const ExportOptions({
    required this.format,
    this.includeArchived = false,
    this.includeDeleted = false,
    this.includeHistory = false,
  });

  final ExportFormat format;
  final bool includeArchived;
  final bool includeDeleted;
  final bool includeHistory;
}

/// One short-lived plaintext record passed directly to a streaming writer.
final class ExportRecord {
  ExportRecord({
    required this.entryId,
    required this.name,
    required this.entryType,
    required this.lifecycle,
    required this.revision,
    required this.payload,
    this.historical = false,
  });

  final String entryId;
  final String name;
  final String entryType;
  final String lifecycle;
  final String revision;
  final Map<String, dynamic> payload;
  final bool historical;

  /// Drops references to decrypted fields immediately after the writer copies
  /// the record. Dart strings cannot be reliably overwritten in managed memory.
  void clear() => payload.clear();
}

final class ExportResult {
  const ExportResult({required this.path, required this.entryCount});

  final String path;
  final int entryCount;
}

enum ExportErrorKind {
  cancelled,
  locked,
  empty,
  corrupt,
  network,
  tooLarge,
  staging,
}

final class ExportException implements Exception {
  const ExportException(this.kind);
  final ExportErrorKind kind;
}
