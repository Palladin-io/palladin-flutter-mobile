enum EntryShareCopyInputError {
  invalidTitle,
  missingFields,
  unexpectedCompletion,
  invalidTotp,
  invalidScript,
  unsupportedContent,
}

final class EntryShareCopyInputException implements Exception {
  const EntryShareCopyInputException(this.kind);
  final EntryShareCopyInputError kind;

  @override
  String toString() => 'EntryShareCopyInputException(${kind.name})';
}

enum EntryShareCopyError { request, cancelled, invalidAuthority, encryption }

final class EntryShareCopyException implements Exception {
  const EntryShareCopyException(this.kind);
  final EntryShareCopyError kind;
  @override
  String toString() => 'EntryShareCopyException(${kind.name})';
}
