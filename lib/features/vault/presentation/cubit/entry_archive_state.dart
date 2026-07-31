import '../../domain/entities/member_index_entry.dart';
import '../../data/services/canonical_entry_detail_service.dart';

enum EntryArchiveSort { labelAscending, labelDescending, typeThenLabel }

sealed class EntryArchiveState {
  const EntryArchiveState();
}

final class EntryArchiveInitial extends EntryArchiveState {
  const EntryArchiveInitial();
}

final class EntryArchiveLocked extends EntryArchiveState {
  const EntryArchiveLocked();
}

final class EntryArchiveError extends EntryArchiveState {
  const EntryArchiveError(this.kind);

  final CanonicalEntryDetailError kind;
}

final class EntryArchiveLoaded extends EntryArchiveState {
  const EntryArchiveLoaded({
    required this.entries,
    this.query = '',
    this.typeFilter,
    this.sort = EntryArchiveSort.labelAscending,
    this.restoringIds = const {},
    this.transientError,
    this.transientErrorTick = 0,
  });

  final List<MemberIndexEntry> entries;
  final String query;
  final int? typeFilter;
  final EntryArchiveSort sort;
  final Set<String> restoringIds;
  final CanonicalEntryDetailError? transientError;
  final int transientErrorTick;

  List<MemberIndexEntry> get visibleEntries {
    final normalized = query.trim().toLowerCase();
    final result = entries
        .where((entry) => typeFilter == null || entry.entryType == typeFilter)
        .where(
          (entry) =>
              normalized.isEmpty ||
              entry.memberLabel.toLowerCase().contains(normalized) ||
              entry.searchFields.any(
                (field) => field.toLowerCase().contains(normalized),
              ),
        )
        .toList(growable: false);
    int byLabel(MemberIndexEntry left, MemberIndexEntry right) {
      final label = left.memberLabel.toLowerCase().compareTo(
        right.memberLabel.toLowerCase(),
      );
      return label != 0 ? label : left.entryId.compareTo(right.entryId);
    }

    result.sort(switch (sort) {
      EntryArchiveSort.labelAscending => byLabel,
      EntryArchiveSort.labelDescending => (left, right) => byLabel(right, left),
      EntryArchiveSort.typeThenLabel => (left, right) {
        final type = left.entryType.compareTo(right.entryType);
        return type != 0 ? type : byLabel(left, right);
      },
    });
    return result;
  }

  EntryArchiveLoaded copyWith({
    List<MemberIndexEntry>? entries,
    String? query,
    Object? typeFilter = _unset,
    EntryArchiveSort? sort,
    Set<String>? restoringIds,
    Object? transientError = _unset,
    int? transientErrorTick,
  }) => EntryArchiveLoaded(
    entries: entries ?? this.entries,
    query: query ?? this.query,
    typeFilter: identical(typeFilter, _unset)
        ? this.typeFilter
        : typeFilter as int?,
    sort: sort ?? this.sort,
    restoringIds: restoringIds ?? this.restoringIds,
    transientError: identical(transientError, _unset)
        ? this.transientError
        : transientError as CanonicalEntryDetailError?,
    transientErrorTick: transientErrorTick ?? this.transientErrorTick,
  );

  static const Object _unset = Object();
}
