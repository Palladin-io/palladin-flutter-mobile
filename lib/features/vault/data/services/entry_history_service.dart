import 'dart:typed_data';

import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/vault_performance_budget.dart';
import '../datasources/entry_remote_datasource.dart';
import 'canonical_entry_detail_service.dart';

/// One immutable encrypted history row returned by the backend.
class EntryHistoryVersion {
  const EntryHistoryVersion({
    required this.revision,
    required this.changedAt,
    required this.changedByType,
    required this.changedById,
    required this.operation,
    required this.encrypted,
  });

  final String revision;
  final DateTime changedAt;
  final String changedByType;
  final String changedById;
  final String operation;
  final Map<String, dynamic> encrypted;
}

class EntryHistoryPage {
  const EntryHistoryPage({required this.items, required this.nextCursor});

  final List<EntryHistoryVersion> items;
  final String? nextCursor;
}

/// Coordinates bounded history reads and canonical N+1 restores.
class EntryHistoryService {
  EntryHistoryService({
    required EntryRemoteDatasource entries,
    required CanonicalEntryDetailService canonical,
  }) : _entries = entries,
       _canonical = canonical;

  static const pageSize = VaultPerformanceBudget.historyPageItems;
  static const maximumLoadedVersions =
      VaultPerformanceBudget.maximumLoadedHistoryVersions;

  final EntryRemoteDatasource _entries;
  final CanonicalEntryDetailService _canonical;

  Future<EntryHistoryPage> loadPage(
    EntryEntity entry, {
    String? beforeRevision,
  }) async {
    final data = await _entries.getEntryHistory(
      entry.vaultId,
      entry.id,
      beforeRevision: beforeRevision,
      pageSize: pageSize,
    );
    final raw = data['items'];
    if (raw is! List || raw.length > pageSize) {
      throw const FormatException('Malformed Entry history page');
    }
    final items = raw
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Malformed history row');
          }
          final row = Map<String, dynamic>.from(value);
          final revision = row['revision'];
          final changedAt = row['changedAt'];
          final actorType = row['changedByType'];
          final actorId = row['changedById'];
          final operation = row['operation'];
          if (revision is! String ||
              changedAt is! String ||
              actorId is! String ||
              actorType == null ||
              operation == null ||
              row['memberSecret'] is! Map) {
            throw const FormatException('Malformed history row');
          }
          return EntryHistoryVersion(
            revision: revision,
            changedAt: DateTime.parse(changedAt).toLocal(),
            changedByType: actorType.toString(),
            changedById: actorId,
            operation: operation.toString(),
            encrypted: row,
          );
        })
        .toList(growable: false);
    final cursor = data['nextBeforeRevision'];
    if (cursor != null && cursor is! String) {
      throw const FormatException('Malformed history cursor');
    }
    return EntryHistoryPage(items: items, nextCursor: cursor as String?);
  }

  Future<CanonicalEntryHistorySnapshot> reveal({
    required EntryEntity entry,
    required EntryHistoryVersion version,
    required Uint8List privateKey,
  }) => _canonical.revealHistoryVersion(
    expected: entry,
    historyItem: version.encrypted,
    memberPrivateKey: privateKey,
  );

  /// Restores content by creating a new canonical revision. The immutable
  /// source row is never edited and the current head is always re-read first.
  Future<EntryEntity> restore({
    required EntryEntity entry,
    required CanonicalEntryHistorySnapshot selected,
    required Uint8List privateKey,
  }) async {
    CanonicalEntrySnapshot? current;
    try {
      current = await _canonical.reveal(
        expected: entry,
        memberPrivateKey: privateKey,
      );
      final typeValue = selected.secret['entryType'];
      if (typeValue is! int) throw const FormatException('Missing entry type');
      return await _canonical.update(
        snapshot: current,
        expected: entry,
        label: selected.secret['memberLabel'] as String? ?? entry.label,
        description: selected.secret['description'] as String? ?? '',
        icon: selected.secret['iconReference'] as String? ?? '',
        type: EntryTypeExtension.fromWire(typeValue),
        content: Map<String, dynamic>.from(selected.payload),
        memberPrivateKey: privateKey,
      );
    } finally {
      current?.payload.clear();
      current?.secret.clear();
      current?.entry.clear();
    }
  }
}
