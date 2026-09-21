enum EntryShareCopyInputError {
  invalidTitle,
  missingFields,
  unexpectedCompletion,
  invalidTotp,
  invalidScript,
  unsupportedContent,
}

final class EntryShareCopyDestination {
  const EntryShareCopyDestination({required this.id, required this.name});
  final String id, name;
}

final class EntryShareCopyDestinations {
  EntryShareCopyDestinations(
    Iterable<EntryShareCopyDestination> items,
    this.unavailable,
  ) : items = List.unmodifiable(items);
  final List<EntryShareCopyDestination> items;
  final int unavailable;
}

final class EntryShareCopyInputException implements Exception {
  const EntryShareCopyInputException(this.kind);
  final EntryShareCopyInputError kind;

  @override
  String toString() => 'EntryShareCopyInputException(${kind.name})';
}

enum EntryShareCopyError { request, cancelled, invalidAuthority, encryption }

final class EntryShareCopyException implements Exception {
  const EntryShareCopyException(this.kind, {this.statusCode});
  final EntryShareCopyError kind;
  final int? statusCode;
  @override
  String toString() => 'EntryShareCopyException(${kind.name})';
}
