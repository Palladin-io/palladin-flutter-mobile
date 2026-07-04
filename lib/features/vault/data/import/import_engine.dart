import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'import_csv.dart';
import 'import_json.dart';
import 'import_models.dart';
import 'import_xml.dart';

/// Top-level import engine: detects a source file's format by structure
/// (not extension — users rename files) and dispatches to the right
/// parser.
///
/// Detection order, from most-specific signature to the generic CSV
/// fallback, mirrors `password-manager-formats.md`:
///   1. ZIP (`PK\x03\x04`) → look inside (.1pux / Dashlane / Proton /
///      single json/csv).
///   2. JSON object → Proton / Bitwarden / Keeper / 1Password / Enpass /
///      Palladin.
///   3. XML `<KeePassFile>` → KeePass.
///   4. CSV → matched profile, else manual column mapping.
///
/// This class never logs — the bytes contain plaintext secrets.
class ImportEngine {
  ImportEngine._();

  /// Parses raw file [bytes] into an [ImportOutcome]. [fileName] is only a
  /// weak hint (used to disambiguate a bare JSON vs CSV when the content
  /// is ambiguous); detection is driven by structure.
  static ImportOutcome parse(Uint8List bytes, {String? fileName}) {
    if (bytes.isEmpty) return const ImportUnsupported(ImportUnsupportedReason.empty);

    if (_isZip(bytes)) return _parseZip(bytes);

    final text = _decodeUtf8(bytes);
    if (text == null || text.trim().isEmpty) {
      return const ImportUnsupported(ImportUnsupportedReason.empty);
    }
    return _parseText(text);
  }

  /// Re-runs CSV parsing with a user-supplied [mapping] after the manual
  /// column-mapper step.
  static ParsedFile parseWithMapping(CsvTable table, ColumnMapping mapping) =>
      ImportCsvParser.parseWithMapping(table, mapping);

  // ── ZIP ────────────────────────────────────────────────────────────

  static ImportOutcome _parseZip(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return const ImportUnsupported(ImportUnsupportedReason.unrecognised);
    }

    String? fileText(String suffix) {
      for (final file in archive.files) {
        if (file.isFile && file.name.toLowerCase().endsWith(suffix)) {
          return _decodeUtf8(file.content as List<int>);
        }
      }
      return null;
    }

    // 1Password .1pux — export.data holds the whole JSON payload.
    final exportData = fileText('export.data');
    if (exportData != null) {
      final root = _tryJsonObject(exportData);
      if (root != null) return ImportParsed(ImportJsonParser.parseOnePassword(root));
    }

    // Proton Pass ZIP — an encrypted PGP blob can't be parsed client-side.
    if (_hasFile(archive, '.pgp')) {
      return const ImportUnsupported(ImportUnsupportedReason.encrypted);
    }
    final protonJson = fileText('.json');
    if (protonJson != null) {
      final root = _tryJsonObject(protonJson);
      if (root != null) return _dispatchJson(root);
    }

    // Dashlane ZIP — the login file is credentials.csv.
    final credentials = fileText('credentials.csv');
    if (credentials != null) {
      final table = ImportCsvParser.toTable(credentials);
      if (table != null) {
        final profile = ImportCsvParser.profileFor(table);
        if (profile != null) {
          return ImportParsed(ImportCsvParser.parseWithProfile(table, profile));
        }
        return ImportNeedsMapping(table);
      }
    }

    // Fallback: a single CSV anywhere in the archive.
    final anyCsv = fileText('.csv');
    if (anyCsv != null) return _parseText(anyCsv);

    return const ImportUnsupported(ImportUnsupportedReason.unrecognised);
  }

  // ── Text (JSON / XML / CSV) ──────────────────────────────────────────

  static ImportOutcome _parseText(String text) {
    final trimmed = text.trimLeft();

    if (trimmed.startsWith('{')) {
      final root = _tryJsonObject(text);
      if (root != null) return _dispatchJson(root);
    }

    if (trimmed.startsWith('<')) {
      final doc = _tryXml(text);
      if (doc != null) {
        if (doc.rootElement.name.local == 'KeePassFile') {
          return ImportParsed(ImportXmlParser.parse(doc));
        }
        return const ImportUnsupported(ImportUnsupportedReason.unrecognised);
      }
    }

    // CSV — match a profile or fall back to manual mapping. A file with a
    // header but no data rows (or an undecodable blob that yields a single
    // junk line) is not a usable CSV.
    final table = ImportCsvParser.toTable(text);
    if (table == null || table.headers.isEmpty || table.rows.isEmpty) {
      return const ImportUnsupported(ImportUnsupportedReason.unrecognised);
    }
    final profile = ImportCsvParser.profileFor(table);
    if (profile != null) {
      return ImportParsed(ImportCsvParser.parseWithProfile(table, profile));
    }
    return ImportNeedsMapping(table);
  }

  static ImportOutcome _dispatchJson(Map<String, dynamic> root) {
    // Proton Pass keys `vaults` as an object; Palladin as an array.
    if (root['vaults'] is Map) return ImportParsed(ImportJsonParser.parseProtonPass(root));
    if (root['vaults'] is List) return ImportParsed(ImportJsonParser.parsePalladin(root));
    if (root['items'] is List &&
        (root['folders'] is List || root['collections'] is List)) {
      return ImportParsed(ImportJsonParser.parseBitwarden(root));
    }
    if (root['records'] is List) return ImportParsed(ImportJsonParser.parseKeeper(root));
    if (root['accounts'] is List) {
      return ImportParsed(ImportJsonParser.parseOnePassword(root));
    }
    // Enpass — items[] with per-field type; check after Bitwarden so its
    // folders/collections signature wins.
    if (root['items'] is List) return ImportParsed(ImportJsonParser.parseEnpass(root));
    return const ImportUnsupported(ImportUnsupportedReason.unrecognised);
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static bool _isZip(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;

  static bool _hasFile(Archive archive, String suffix) => archive.files.any(
        (f) => f.isFile && f.name.toLowerCase().endsWith(suffix),
      );

  static String? _decodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
  }

  static Map<String, dynamic>? _tryJsonObject(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static XmlDocument? _tryXml(String text) {
    try {
      return XmlDocument.parse(text);
    } catch (_) {
      return null;
    }
  }
}
