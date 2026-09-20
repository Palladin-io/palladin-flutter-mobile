import 'entry_share.dart';

final class EntryShareFieldChoice {
  const EntryShareFieldChoice({
    required this.id,
    required this.label,
    required this.type,
    required this.value,
    required this.selectedByDefault,
  });

  final String id, label, type, value;
  final bool selectedByDefault;
}

final class UnsupportedEntryShareField {
  const UnsupportedEntryShareField({required this.id, required this.label});
  final String id, label;
}

final class EntryShareSelection {
  EntryShareSelection({
    required this.title,
    required this.entryType,
    required List<EntryShareFieldChoice> choices,
    required List<UnsupportedEntryShareField> unsupported,
  }) : choices = List.unmodifiable(choices),
       unsupported = List.unmodifiable(unsupported);

  final String title, entryType;
  final List<EntryShareFieldChoice> choices;
  final List<UnsupportedEntryShareField> unsupported;

  EntryShareSnapshot select(Iterable<String> selectedIds) {
    const invalid = EntryShareException(EntryShareErrorKind.invalidSnapshot);
    final requested = selectedIds.toList(growable: false);
    final ids = requested.toSet();
    final available = choices.map((field) => field.id).toSet();
    if (ids.isEmpty ||
        requested.length != ids.length ||
        choices.length != available.length ||
        !available.containsAll(ids)) {
      throw invalid;
    }
    return EntryShareSnapshot.fromJson({
      'schema': EntryShareSnapshot.schema,
      'title': title,
      'entryType': entryType,
      'fields': [
        for (final field in choices)
          if (ids.contains(field.id))
            {
              'id': field.id,
              'label': field.label,
              'type': field.type,
              'value': field.value,
            },
      ],
    });
  }
}
