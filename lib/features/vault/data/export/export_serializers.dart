import 'dart:convert';
import 'dart:typed_data';

import 'export_models.dart';
import 'protected_export_staging.dart';

/// Incremental serializer writing bounded UTF-8 chunks to protected staging.
abstract interface class ExportWriter {
  Future<void> start({required String vaultId, required String vaultName});
  Future<void> write(ExportRecord record);
  Future<String> finish();
  Future<void> abort();
  int get bytesWritten;
}

final class ProtectedExportWriter implements ExportWriter {
  ProtectedExportWriter({
    required ProtectedExportStaging staging,
    required ExportFormat format,
    this.maximumBytes = 50 * 1024 * 1024,
  }) : _staging = staging,
       _format = format;

  final ProtectedExportStaging _staging;
  final ExportFormat _format;
  final int maximumBytes;
  ProtectedExportSink? _sink;
  int _bytesWritten = 0;
  int _records = 0;

  @override
  int get bytesWritten => _bytesWritten;

  @override
  Future<void> start({
    required String vaultId,
    required String vaultName,
  }) async {
    _sink = await _staging.create(fileExtension: _format.extension);
    if (_format == ExportFormat.csv) {
      await _append(
        'entryId,name,type,lifecycle,revision,historical,payload\r\n',
      );
    } else {
      await _append(
        '{"format":"palladin","formatVersion":2,'
        '"lifecycleSchemaVersion":1,"vault":${jsonEncode({'id': vaultId, 'name': vaultName})},'
        '"entries":[',
      );
    }
  }

  @override
  Future<void> write(ExportRecord record) async {
    if (_format == ExportFormat.csv) {
      await _append(
        [
          record.entryId,
          record.name,
          record.entryType,
          record.lifecycle,
          record.revision,
          record.historical.toString(),
          jsonEncode(record.payload),
        ].map(_escapeCsv).join(','),
      );
      await _append('\r\n');
    } else {
      if (_records > 0) await _append(',');
      await _append(
        jsonEncode({
          'entryId': record.entryId,
          'name': record.name,
          'type': record.entryType,
          'lifecycle': record.lifecycle,
          'revision': record.revision,
          'historical': record.historical,
          'payload': record.payload,
        }),
      );
    }
    _records++;
  }

  @override
  Future<String> finish() async {
    if (_format == ExportFormat.json) await _append(']}');
    return (_sink ?? (throw StateError('Writer not started'))).finish();
  }

  @override
  Future<void> abort() async => _sink?.abort();

  Future<void> _append(String value) async {
    final bytes = Uint8List.fromList(utf8.encode(value));
    try {
      if (_bytesWritten + bytes.length > maximumBytes) {
        throw const ExportException(ExportErrorKind.tooLarge);
      }
      await (_sink ?? (throw StateError('Writer not started'))).append(bytes);
      _bytesWritten += bytes.length;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
