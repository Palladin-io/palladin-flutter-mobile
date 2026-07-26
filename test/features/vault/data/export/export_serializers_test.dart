import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/export/export_models.dart';
import 'package:mobile_palladin/features/vault/data/export/export_serializers.dart';
import 'package:mobile_palladin/features/vault/data/export/protected_export_staging.dart';

void main() {
  test('JSON streams format/lifecycle revisions and records', () async {
    final staging = _MemoryStaging();
    final writer = ProtectedExportWriter(
      staging: staging,
      format: ExportFormat.json,
    );
    await writer.start(vaultId: 'v-1', vaultName: 'Personal');
    await writer.write(
      ExportRecord(
        entryId: 'e-1',
        name: 'GitHub',
        entryType: '1',
        lifecycle: 'archived',
        revision: '7',
        historical: true,
        payload: {'username': 'octocat', 'password': 'secret'},
      ),
    );
    expect(await writer.finish(), '/protected/export.json');
    final root = jsonDecode(staging.text) as Map<String, dynamic>;
    expect(root['formatVersion'], 2);
    expect(root['lifecycleSchemaVersion'], 1);
    final record = (root['entries'] as List).single as Map<String, dynamic>;
    expect(record['lifecycle'], 'archived');
    expect(record['revision'], '7');
    expect(record['historical'], isTrue);
    expect(staging.appendSizes.length, greaterThan(2));
  });

  test('CSV escapes payload and carries revision metadata', () async {
    final staging = _MemoryStaging();
    final writer = ProtectedExportWriter(
      staging: staging,
      format: ExportFormat.csv,
    );
    await writer.start(vaultId: 'v-1', vaultName: 'Personal');
    await writer.write(
      ExportRecord(
        entryId: 'e-1',
        name: 'Acme, Inc',
        entryType: '0',
        lifecycle: 'active',
        revision: '1',
        payload: {'value': 'a"b'},
      ),
    );
    await writer.finish();
    expect(staging.text, startsWith('entryId,name,type,lifecycle,revision'));
    expect(staging.text, contains('"Acme, Inc"'));
    expect(staging.appendSizes.every((size) => size < 256 * 1024), isTrue);
  });

  test('aborts staging when byte limit is exceeded', () async {
    final staging = _MemoryStaging();
    final writer = ProtectedExportWriter(
      staging: staging,
      format: ExportFormat.json,
      maximumBytes: 180,
    );
    await writer.start(vaultId: 'v', vaultName: 'v');
    await expectLater(
      writer.write(
        ExportRecord(
          entryId: 'e',
          name: 'n',
          entryType: '0',
          lifecycle: 'active',
          revision: '1',
          payload: {'value': 'x' * 200},
        ),
      ),
      throwsA(isA<ExportException>()),
    );
    await writer.abort();
    expect(staging.sink.aborted, isTrue);
  });
}

final class _MemoryStaging implements ProtectedExportStaging {
  final _MemorySink sink = _MemorySink();
  String get text => utf8.decode(sink.bytes);
  List<int> get appendSizes => sink.appendSizes;
  @override
  Future<int> cleanupExports() async => 0;
  @override
  Future<ProtectedExportSink> create({required String fileExtension}) async =>
      sink;
  @override
  Future<bool> delete(String path) async => true;
  @override
  Future<int> sweepStaleExports() async => 0;
}

final class _MemorySink implements ProtectedExportSink {
  final List<int> bytes = [];
  final List<int> appendSizes = [];
  bool aborted = false;
  @override
  Future<void> append(Uint8List value) async {
    appendSizes.add(value.length);
    bytes.addAll(value);
  }

  @override
  Future<void> abort() async {
    aborted = true;
  }

  @override
  Future<String> finish() async => '/protected/export.json';
}
