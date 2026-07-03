import 'dart:convert';

import 'export_models.dart';

/// Pure serializers for the two Palladin export formats. Both are
/// client-side only — the plaintext file never touches the server.
///
/// * [toPalladinCsv] — `name,url,username,password,note,totp,folder`. The
///   `name,url,username,password,note` prefix is importable 1:1 into
///   Chrome / Bitwarden / generic; `totp,folder` are a safe superset
///   ignored by importers that don't know them.
/// * [toPalladinJson] — the native, lossless v1 schema (round-trips back
///   through the import wizard).
class ExportSerializer {
  ExportSerializer._();

  static const List<String> csvHeaders = [
    'name',
    'url',
    'username',
    'password',
    'note',
    'totp',
    'folder',
  ];

  /// Serializes [records] to RFC 4180 CSV. Fields containing a comma,
  /// quote, or newline are double-quoted with embedded quotes doubled.
  static String toPalladinCsv(List<ExportRecord> records) {
    final buffer = StringBuffer();
    buffer.writeln(csvHeaders.map(_escapeCsv).join(','));
    for (final r in records) {
      buffer.writeln([
        r.name,
        r.url ?? '',
        r.username ?? '',
        r.password ?? '',
        r.notes ?? '',
        r.totp ?? '',
        r.folder ?? '',
      ].map(_escapeCsv).join(','));
    }
    return buffer.toString();
  }

  /// Serializes [records] to the Palladin JSON v1 schema. [vaultName]
  /// groups the entries under a single vault object; [exportedAt] is
  /// injectable for deterministic tests.
  static String toPalladinJson(
    List<ExportRecord> records, {
    required String vaultName,
    String vaultId = '',
    DateTime? exportedAt,
  }) {
    final root = {
      'version': 1,
      'exportedAt': (exportedAt ?? DateTime.now().toUtc()).toIso8601String(),
      'encrypted': false,
      'vaults': [
        {
          'id': vaultId,
          'name': vaultName,
          'entries': [
            for (final r in records)
              {
                'name': r.name,
                if (r.username != null) 'username': r.username,
                if (r.password != null) 'password': r.password,
                if (r.url != null) 'urlDomain': r.url,
                if (r.notes != null) 'notes': r.notes,
                if (r.totp != null) 'totp': r.totp,
              },
          ],
        },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(root);
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
