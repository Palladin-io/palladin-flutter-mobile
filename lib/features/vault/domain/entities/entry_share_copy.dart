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
