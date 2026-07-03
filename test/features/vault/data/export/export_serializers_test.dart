import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/export/export_models.dart';
import 'package:mobile_palladin/features/vault/data/export/export_serializers.dart';
import 'package:mobile_palladin/features/vault/data/import/import_engine.dart';
import 'package:mobile_palladin/features/vault/data/import/import_models.dart';

void main() {
  group('toPalladinCsv', () {
    test('writes the canonical header row', () {
      final csv = ExportSerializer.toPalladinCsv(const []);
      expect(csv.trim(), 'name,url,username,password,note,totp,folder');
    });

    test('escapes fields with commas, quotes and newlines (RFC 4180)', () {
      final csv = ExportSerializer.toPalladinCsv([
        const ExportRecord(
          name: 'Acme, Inc',
          username: 'a"b',
          password: 'p',
          notes: 'multi\nline',
        ),
      ]);
      final lines = const LineSplitter().convert(csv);
      expect(lines[1], contains('"Acme, Inc"'));
      expect(lines[1], contains('"a""b"'));
      expect(csv, contains('"multi\nline"'));
    });
  });

  group('toPalladinJson', () {
    test('emits the v1 schema with a single vault', () {
      final json = ExportSerializer.toPalladinJson(
        [
          const ExportRecord(
            name: 'GitHub',
            username: 'octocat',
            password: 'S3cr3t!',
            url: 'github.com',
            totp: 'otpauth://totp/x?secret=ABC',
          ),
        ],
        vaultName: 'Personal',
        vaultId: 'v-1',
        exportedAt: DateTime.utc(2026, 7, 4),
      );
      final root = jsonDecode(json) as Map<String, dynamic>;
      expect(root['version'], 1);
      expect(root['encrypted'], false);
      expect(root['exportedAt'], '2026-07-04T00:00:00.000Z');
      final vault = (root['vaults'] as List).single as Map<String, dynamic>;
      expect(vault['name'], 'Personal');
      final entry = (vault['entries'] as List).single as Map<String, dynamic>;
      expect(entry['name'], 'GitHub');
      expect(entry['totp'], 'otpauth://totp/x?secret=ABC');
    });
  });

  group('round-trip', () {
    test('Palladin JSON export re-imports through the wizard losslessly', () {
      final json = ExportSerializer.toPalladinJson(
        [
          const ExportRecord(
            name: 'GitHub',
            username: 'octocat',
            password: 'S3cr3t!',
            url: 'github.com',
            notes: 'a note',
            totp: 'otpauth://totp/x?secret=ABC',
          ),
        ],
        vaultName: 'Personal',
      );
      final outcome = ImportEngine.parse(_bytes(json));
      expect(outcome, isA<ImportParsed>());
      final entry = (outcome as ImportParsed).result.entries.single;
      expect(entry.name, 'GitHub');
      expect(entry.username, 'octocat');
      expect(entry.password, 'S3cr3t!');
      expect(entry.urlDomain, 'github.com');
      expect(entry.notes, 'a note');
      expect(entry.totp, 'otpauth://totp/x?secret=ABC');
    });

    test('Palladin CSV export re-imports through the wizard', () {
      final csv = ExportSerializer.toPalladinCsv([
        const ExportRecord(
          name: 'GitHub',
          username: 'octocat',
          password: 'S3cr3t!',
          url: 'github.com',
          totp: 'otpauth://totp/x?secret=ABC',
          folder: 'Personal',
        ),
      ]);
      final outcome = ImportEngine.parse(_bytes(csv));
      expect(outcome, isA<ImportParsed>());
      final result = (outcome as ImportParsed).result;
      expect(result.format, ImportFormat.palladinCsv);
      final entry = result.entries.single;
      expect(entry.password, 'S3cr3t!');
      expect(entry.totp, 'otpauth://totp/x?secret=ABC');
    });
  });
}

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));
