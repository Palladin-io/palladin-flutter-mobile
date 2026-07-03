import 'package:csv/csv.dart';

import 'import_models.dart';
import 'import_normalizer.dart';

/// Declarative description of one manager's CSV export: how to recognise
/// it from its header set and how to map its columns onto Palladin
/// fields. Adding a new CSV format is a matter of appending a profile —
/// no new parsing code.
class CsvProfile {
  const CsvProfile({
    required this.format,
    required this.matches,
    this.nameKey,
    this.usernameKeys = const [],
    this.passwordKey,
    this.urlKey,
    this.notesKey,
    this.totpKey,
    this.folderKey,
    this.totpIsBareSecret = false,
    this.isSkippableRow,
  });

  final ImportFormat format;

  /// Returns `true` when [normalizedHeaders] (lower-cased) identify this
  /// profile. Ordered most-specific-first by the detector.
  final bool Function(List<String> normalizedHeaders) matches;

  /// Header names (lower-case) for each field. `null` means the source
  /// has no such column — e.g. Firefox has no name column, so the name
  /// is synthesised from the URL host during normalisation.
  final String? nameKey;

  /// Username may live under several columns (Dashlane username /
  /// username2 / username3) — the first non-empty wins.
  final List<String> usernameKeys;
  final String? passwordKey;
  final String? urlKey;
  final String? notesKey;
  final String? totpKey;
  final String? folderKey;

  /// When the TOTP column carries a bare Base32 secret (Dashlane
  /// `otpSecret`) rather than a full `otpauth://` URI.
  final bool totpIsBareSecret;

  /// Optional predicate that flags a row as a non-login (LastPass secure
  /// notes have `url == http://sn`) so it is counted as skipped.
  final bool Function(Map<String, String> row)? isSkippableRow;
}

/// CSV parsing engine — profile matching and row → [ParsedEntry] mapping.
class ImportCsvParser {
  ImportCsvParser._();

  /// The registered profiles, ordered most-specific signature first so
  /// the generic fallback only matches when nothing else does.
  static final List<CsvProfile> profiles = [
    // Firefox — unique httpRealm/formActionOrigin/guid trio, no title.
    CsvProfile(
      format: ImportFormat.firefoxCsv,
      matches: (h) =>
          h.contains('httprealm') &&
          h.contains('formactionorigin') &&
          h.contains('guid'),
      usernameKeys: const ['username'],
      passwordKey: 'password',
      urlKey: 'url',
    ),
    // Dashlane single credentials.csv — otpSecret + username2 + title.
    CsvProfile(
      format: ImportFormat.dashlaneCsv,
      matches: (h) =>
          h.contains('otpsecret') &&
          h.contains('username2') &&
          h.contains('title'),
      nameKey: 'title',
      usernameKeys: const ['username', 'username2', 'username3'],
      passwordKey: 'password',
      urlKey: 'url',
      notesKey: 'note',
      totpKey: 'otpsecret',
      folderKey: 'category',
      totpIsBareSecret: true,
    ),
    // LastPass — extra + grouping + fav; secure notes use url == http://sn.
    CsvProfile(
      format: ImportFormat.lastpassCsv,
      matches: (h) =>
          h.contains('extra') && h.contains('grouping') && h.contains('fav'),
      nameKey: 'name',
      usernameKeys: const ['username'],
      passwordKey: 'password',
      urlKey: 'url',
      notesKey: 'extra',
      totpKey: 'totp',
      folderKey: 'grouping',
      isSkippableRow: (row) => (row['url'] ?? '').toLowerCase() == 'http://sn',
    ),
    // Bitwarden CSV — login_uri/login_username/login_password prefixes.
    CsvProfile(
      format: ImportFormat.bitwardenCsv,
      matches: (h) =>
          h.contains('login_uri') &&
          h.contains('login_username') &&
          h.contains('login_password'),
      nameKey: 'name',
      usernameKeys: const ['login_username'],
      passwordKey: 'login_password',
      urlKey: 'login_uri',
      notesKey: 'notes',
      totpKey: 'login_totp',
      folderKey: 'folder',
    ),
    // 1Password 8 CSV — Title + OTPAuth + Archived + Tags.
    CsvProfile(
      format: ImportFormat.onePasswordCsv,
      matches: (h) =>
          h.contains('title') &&
          h.contains('otpauth') &&
          h.contains('archived') &&
          h.contains('tags'),
      nameKey: 'title',
      usernameKeys: const ['username'],
      passwordKey: 'password',
      urlKey: 'url',
      notesKey: 'notes',
      totpKey: 'otpauth',
      folderKey: 'tags',
    ),
    // Safari / iCloud Keychain — Title + OTPAuth, no Archived/Tags.
    CsvProfile(
      format: ImportFormat.safariCsv,
      matches: (h) =>
          h.contains('title') &&
          h.contains('otpauth') &&
          !h.contains('archived'),
      nameKey: 'title',
      usernameKeys: const ['username'],
      passwordKey: 'password',
      urlKey: 'url',
      notesKey: 'notes',
      totpKey: 'otpauth',
    ),
    // RoboForm — Pwd is the signature column.
    CsvProfile(
      format: ImportFormat.roboformCsv,
      matches: (h) =>
          h.contains('pwd') && h.contains('name') && h.contains('login'),
      nameKey: 'name',
      usernameKeys: const ['login'],
      passwordKey: 'pwd',
      urlKey: 'url',
      notesKey: 'note',
      folderKey: 'folder',
    ),
    // NordPass — one unified CSV for all item types; `cardholdername` is
    // the signature that separates it from a Palladin CSV (which also has
    // a `folder` column but never `cardholdername`).
    CsvProfile(
      format: ImportFormat.nordpassCsv,
      matches: (h) =>
          h.contains('name') &&
          h.contains('url') &&
          h.contains('username') &&
          h.contains('password') &&
          h.contains('cardholdername'),
      nameKey: 'name',
      usernameKeys: const ['username'],
      passwordKey: 'password',
      urlKey: 'url',
      notesKey: 'note',
      folderKey: 'folder',
    ),
    // Palladin's own CSV export — round-trips totp + folder.
    CsvProfile(
      format: ImportFormat.palladinCsv,
      matches: (h) =>
          h.contains('name') &&
          h.contains('url') &&
          h.contains('username') &&
          h.contains('password') &&
          h.contains('totp'),
      nameKey: 'name',
      usernameKeys: const ['username'],
      passwordKey: 'password',
      urlKey: 'url',
      notesKey: 'note',
      totpKey: 'totp',
      folderKey: 'folder',
    ),
    // Generic / Chromium fallback — name,url,username,password[,note].
    CsvProfile(
      format: ImportFormat.genericCsv,
      matches: (h) =>
          h.contains('name') &&
          h.contains('url') &&
          h.contains('username') &&
          h.contains('password'),
      nameKey: 'name',
      usernameKeys: const ['username'],
      passwordKey: 'password',
      urlKey: 'url',
      // Chromium uses `note`; row lookup falls back to `notes`.
      notesKey: 'note',
    ),
  ];

  /// Splits raw CSV [text] into a [CsvTable]. Strips a leading UTF-8 BOM
  /// and drops fully-empty rows. Returns `null` when there is no header.
  static CsvTable? toTable(String text) {
    final clean = text.startsWith('﻿') ? text.substring(1) : text;
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(clean.replaceAll('\r\n', '\n'));
    if (rows.isEmpty) return null;
    final headers = rows.first.map((c) => c.toString()).toList();
    final dataRows = rows
        .skip(1)
        .map((r) => r.map((c) => c.toString()).toList())
        .where((r) => r.any((c) => c.trim().isNotEmpty))
        .toList();
    return CsvTable(headers: headers, rows: dataRows);
  }

  /// Finds the profile matching [table]'s header, or `null` when the CSV
  /// is unrecognised (the caller then offers manual column mapping).
  static CsvProfile? profileFor(CsvTable table) {
    final headers = table.normalizedHeaders;
    for (final profile in profiles) {
      if (profile.matches(headers)) return profile;
    }
    return null;
  }

  /// Parses [table] with a matched [profile] into login entries.
  static ParsedFile parseWithProfile(CsvTable table, CsvProfile profile) {
    final headerIndex = _headerIndex(table.normalizedHeaders);
    final entries = <ParsedEntry>[];
    var skipped = 0;

    for (final row in table.rows) {
      final map = _rowMap(headerIndex, row);
      if (profile.isSkippableRow?.call(map) ?? false) {
        skipped++;
        continue;
      }
      final username = _firstNonEmpty(map, profile.usernameKeys);
      final notes = profile.notesKey != null
          ? (map[profile.notesKey!] ?? map['notes'])
          : null;
      final entry = ImportNormalizer.build(
        name: profile.nameKey != null ? map[profile.nameKey!] : null,
        username: username,
        password: profile.passwordKey != null ? map[profile.passwordKey!] : null,
        url: profile.urlKey != null ? map[profile.urlKey!] : null,
        notes: notes,
        rawTotp: profile.totpKey != null ? map[profile.totpKey!] : null,
        folder: profile.folderKey != null ? map[profile.folderKey!] : null,
        isBareTotpSecret: profile.totpIsBareSecret,
      );
      if (entry == null) {
        skipped++;
      } else {
        entries.add(entry);
      }
    }
    return ParsedFile(
      format: profile.format,
      entries: entries,
      skippedCount: skipped,
    );
  }

  /// Parses [table] using a user-supplied [ColumnMapping] (manual mode).
  static ParsedFile parseWithMapping(CsvTable table, ColumnMapping mapping) {
    final entries = <ParsedEntry>[];
    var skipped = 0;
    for (final row in table.rows) {
      final entry = ImportNormalizer.build(
        name: _cell(row, mapping.nameIndex),
        username: _cell(row, mapping.usernameIndex),
        password: _cell(row, mapping.passwordIndex),
        url: _cell(row, mapping.urlIndex),
        notes: _cell(row, mapping.notesIndex),
        rawTotp: _cell(row, mapping.totpIndex),
      );
      if (entry == null) {
        skipped++;
      } else {
        entries.add(entry);
      }
    }
    return ParsedFile(
      format: ImportFormat.manualCsv,
      entries: entries,
      skippedCount: skipped,
    );
  }

  static Map<String, int> _headerIndex(List<String> normalizedHeaders) {
    final index = <String, int>{};
    for (var i = 0; i < normalizedHeaders.length; i++) {
      index.putIfAbsent(normalizedHeaders[i], () => i);
    }
    return index;
  }

  static Map<String, String> _rowMap(Map<String, int> headerIndex, List<String> row) {
    final map = <String, String>{};
    headerIndex.forEach((key, i) {
      if (i < row.length) map[key] = row[i];
    });
    return map;
  }

  static String? _firstNonEmpty(Map<String, String> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static String? _cell(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return null;
    return row[index];
  }
}
