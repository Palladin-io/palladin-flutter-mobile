import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../domain/entities/member_index_entry.dart';
import '../datasources/entry_remote_datasource.dart';
import '../services/canonical_entry_detail_service.dart';
import '../services/member_entry_list_service.dart';
import 'export_models.dart';
import 'export_serializers.dart';

typedef ExportWriterFactory = ExportWriter Function(ExportFormat format);

/// Canonical, local-only export coordinator.
///
/// It synchronizes the encrypted Member index, opens one Vault key session,
/// fetches/decrypts MemberSecret records strictly one at a time, and streams
/// each record into protected staging. No plaintext is sent to the backend.
final class CanonicalExportService {
  CanonicalExportService({
    required MemberEntryListLoader index,
    required CanonicalEntryDetailService canonical,
    required EntryRemoteDatasource entries,
    required ExportWriterFactory writerFactory,
    this.pageSize = 100,
    this.maximumEntries = 20000,
    this.maximumExportRecords = 50000,
  }) : _index = index,
       _canonical = canonical,
       _entries = entries,
       _writerFactory = writerFactory;

  final MemberEntryListLoader _index;
  final CanonicalEntryDetailService _canonical;
  final EntryRemoteDatasource _entries;
  final ExportWriterFactory _writerFactory;
  final int pageSize;
  final int maximumEntries;
  final int maximumExportRecords;
  int _epoch = 0;

  Future<ExportResult> export({
    required String vaultId,
    required String vaultName,
    required ExportOptions options,
    required Uint8List memberPrivateKey,
  }) async {
    if (memberPrivateKey.length != 32) {
      throw const ExportException(ExportErrorKind.locked);
    }
    final epoch = ++_epoch;
    final keyCopy = Uint8List.fromList(memberPrivateKey);
    final writer = _writerFactory(options.format);
    CanonicalEntryExportSession? session;
    var started = false;
    var count = 0;
    try {
      final all = await _index.load(
        vaultId: vaultId,
        memberPrivateKey: keyCopy,
      );
      _check(epoch);
      if (all.length > maximumEntries) {
        throw const ExportException(ExportErrorKind.tooLarge);
      }
      final selected =
          all
              .where((entry) {
                if (entry.corrupt) return false;
                return switch (entry.state) {
                  MemberEntryState.active => true,
                  MemberEntryState.archived => options.includeArchived,
                  MemberEntryState.deleted => options.includeDeleted,
                  MemberEntryState.unknown => false,
                };
              })
              .toList(growable: false)
            ..sort((left, right) => left.entryId.compareTo(right.entryId));
      if (selected.isEmpty) {
        throw const ExportException(ExportErrorKind.empty);
      }
      session = await _canonical.beginExportSession(
        vaultId: vaultId,
        memberPrivateKey: keyCopy,
      );
      _check(epoch);
      await writer.start(vaultId: vaultId, vaultName: vaultName);
      started = true;

      for (var offset = 0; offset < selected.length; offset += pageSize) {
        final end = (offset + pageSize).clamp(0, selected.length);
        for (final indexed in selected.sublist(offset, end)) {
          _check(epoch);
          final snapshot = await session.revealCurrent(indexed);
          try {
            await writer.write(_record(indexed, snapshot, historical: false));
            count++;
          } finally {
            snapshot.clear();
          }
          _checkLimit(count);
          if (options.includeHistory) {
            count += await _writeHistory(
              epoch: epoch,
              indexed: indexed,
              session: session,
              writer: writer,
              alreadyWritten: count,
            );
          }
        }
      }
      _check(epoch);
      final path = await writer.finish();
      started = false;
      return ExportResult(path: path, entryCount: count);
    } on ExportException {
      rethrow;
    } on CanonicalEntryDetailException catch (error) {
      throw ExportException(
        error.kind == CanonicalEntryDetailError.network
            ? ExportErrorKind.network
            : ExportErrorKind.corrupt,
      );
    } on DioException {
      throw const ExportException(ExportErrorKind.network);
    } on FormatException {
      throw const ExportException(ExportErrorKind.corrupt);
    } catch (_) {
      throw const ExportException(ExportErrorKind.staging);
    } finally {
      if (started) {
        try {
          await writer.abort();
        } catch (_) {
          // Best effort: startup/lock stale sweep is the second cleanup layer.
        }
      }
      session?.close();
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }

  Future<int> _writeHistory({
    required int epoch,
    required MemberIndexEntry indexed,
    required CanonicalEntryExportSession session,
    required ExportWriter writer,
    required int alreadyWritten,
  }) async {
    var written = 0;
    String? cursor;
    final cursors = <String>{};
    do {
      _check(epoch);
      final page = await _entries.getEntryHistory(
        session.vaultId,
        indexed.entryId,
        beforeRevision: cursor,
        pageSize: 20,
      );
      final items = page['items'];
      if (items is! List || items.length > 20) {
        throw const FormatException('Malformed history page');
      }
      for (final raw in items) {
        if (raw is! Map) throw const FormatException('Malformed history row');
        final item = Map<String, dynamic>.from(raw);
        // Current head is already exported above.
        if (item['revision'] == indexed.revision) continue;
        final snapshot = await session.revealHistory(
          expected: indexed,
          historyItem: item,
        );
        try {
          await writer.write(_record(indexed, snapshot, historical: true));
          written++;
        } finally {
          snapshot.clear();
        }
        _checkLimit(alreadyWritten + written);
        _check(epoch);
      }
      final next = page['nextBeforeRevision'];
      if (next != null && (next is! String || !cursors.add(next))) {
        throw const FormatException('Invalid history cursor');
      }
      cursor = next as String?;
    } while (cursor != null);
    return written;
  }

  ExportRecord _record(
    MemberIndexEntry indexed,
    CanonicalEntrySnapshot snapshot, {
    required bool historical,
  }) {
    final secret = snapshot.secret;
    final revision = snapshot.entry['currentRevision'] ?? secret['revision'];
    if (revision is! String) throw const FormatException('Missing revision');
    return ExportRecord(
      entryId: indexed.entryId,
      name: secret['memberLabel'] as String? ?? indexed.memberLabel,
      entryType: indexed.entryType.toString(),
      lifecycle: indexed.state.name,
      revision: revision,
      historical: historical,
      payload: snapshot.payload,
    );
  }

  void cancel() => _epoch++;

  void _check(int epoch) {
    if (epoch != _epoch) {
      throw const ExportException(ExportErrorKind.cancelled);
    }
  }

  void _checkLimit(int count) {
    if (count > maximumExportRecords) {
      throw const ExportException(ExportErrorKind.tooLarge);
    }
  }
}
