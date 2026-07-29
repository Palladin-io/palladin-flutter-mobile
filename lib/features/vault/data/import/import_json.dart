import 'import_models.dart';
import 'import_normalizer.dart';

/// Parsers for the JSON-based export formats. Each function takes the
/// already-decoded root object and returns login entries; detection
/// (which parser to call) lives in the import engine.
class ImportJsonParser {
  ImportJsonParser._();

  /// Bitwarden unencrypted JSON — `{ items: [...], folders|collections }`.
  /// Only `type == 1` (login) items become entries.
  static ParsedFile parseBitwarden(Map<String, dynamic> root) {
    final folderNames = _bitwardenFolderNames(root);
    final items = _list(root['items']);
    final entries = <ParsedEntry>[];
    var skipped = 0;

    for (final raw in items) {
      final item = _map(raw);
      if (item == null) continue;
      final login = _map(item['login']);
      if (item['type'] != 1 || login == null) {
        skipped++;
        continue;
      }
      final uris = _list(login['uris']);
      final firstUri = uris.isNotEmpty
          ? (_map(uris.first)?['uri'] as String?)
          : null;
      final extraUris = uris.length > 1
          ? uris
                .skip(1)
                .map((u) => _map(u)?['uri'] as String?)
                .whereType<String>()
          : const <String>[];
      final folderId = item['folderId'] as String?;
      final entry = ImportNormalizer.build(
        name: item['name'] as String?,
        username: login['username'] as String?,
        password: login['password'] as String?,
        url: firstUri,
        notes: _appendUris(item['notes'] as String?, extraUris),
        rawTotp: login['totp'] as String?,
        folder: folderId != null ? folderNames[folderId] : null,
      );
      if (entry == null) {
        skipped++;
      } else {
        entries.add(entry);
      }
    }
    return ParsedFile(
      format: ImportFormat.bitwardenJson,
      entries: entries,
      skippedCount: skipped,
    );
  }

  /// Keeper JSON — `{ records: [{ title, login, password, login_url, notes }] }`.
  static ParsedFile parseKeeper(Map<String, dynamic> root) {
    final records = _list(root['records']);
    final entries = <ParsedEntry>[];
    var skipped = 0;
    for (final raw in records) {
      final rec = _map(raw);
      if (rec == null) continue;
      final folders = _list(rec['folders']);
      final folder = folders.isNotEmpty
          ? (_map(folders.first)?['folder'] as String?)
          : null;
      final entry = ImportNormalizer.build(
        name: rec['title'] as String?,
        username: rec['login'] as String?,
        password: rec['password'] as String?,
        url: rec['login_url'] as String?,
        notes: rec['notes'] as String?,
        folder: folder,
      );
      if (entry == null) {
        skipped++;
      } else {
        entries.add(entry);
      }
    }
    return ParsedFile(
      format: ImportFormat.keeperJson,
      entries: entries,
      skippedCount: skipped,
    );
  }

  /// Proton Pass JSON — `{ vaults: { <id>: { name, items: [...] } } }` where
  /// `vaults` is an object keyed by vault id.
  static ParsedFile parseProtonPass(Map<String, dynamic> root) {
    final vaults = _map(root['vaults']) ?? const {};
    final entries = <ParsedEntry>[];
    var skipped = 0;
    for (final vaultRaw in vaults.values) {
      final vault = _map(vaultRaw);
      if (vault == null) continue;
      final vaultName = vault['name'] as String?;
      for (final itemRaw in _list(vault['items'])) {
        final item = _map(itemRaw);
        final data = _map(item?['data']);
        final content = _map(data?['content']);
        final metadata = _map(data?['metadata']);
        if (content == null) {
          skipped++;
          continue;
        }
        // Login username may live under itemUsername, username, or email.
        final username =
            (content['itemUsername'] as String?) ??
            (content['username'] as String?) ??
            (content['itemEmail'] as String?) ??
            (content['email'] as String?);
        final urls = _list(content['urls']);
        final firstUrl = urls.isNotEmpty ? urls.first as String? : null;
        final entry = ImportNormalizer.build(
          name: metadata?['name'] as String?,
          username: username,
          password: content['password'] as String?,
          url: firstUrl,
          notes: metadata?['note'] as String?,
          rawTotp: content['totpUri'] as String?,
          folder: vaultName,
        );
        if (entry == null) {
          skipped++;
        } else {
          entries.add(entry);
        }
      }
    }
    return ParsedFile(
      format: ImportFormat.protonPassJson,
      entries: entries,
      skippedCount: skipped,
    );
  }

  /// 1Password `export.data` JSON — `accounts[].vaults[].items[]`. Also the
  /// payload extracted from a `.1pux` archive.
  static ParsedFile parseOnePassword(Map<String, dynamic> root) {
    final entries = <ParsedEntry>[];
    var skipped = 0;
    for (final accRaw in _list(root['accounts'])) {
      final acc = _map(accRaw);
      for (final vaultRaw in _list(acc?['vaults'])) {
        final vault = _map(vaultRaw);
        final vaultName = _map(vault?['attrs'])?['name'] as String?;
        for (final itemRaw in _list(vault?['items'])) {
          final item = _map(itemRaw);
          final overview = _map(item?['overview']);
          final details = _map(item?['details']);
          if (overview == null || details == null) {
            skipped++;
            continue;
          }
          final loginFields = _list(details['loginFields']);
          final username = _designation(loginFields, 'username');
          final password = _designation(loginFields, 'password');
          if (username == null && password == null) {
            skipped++;
            continue;
          }
          final urls = _list(overview['urls']);
          final url =
              overview['url'] as String? ??
              (urls.isNotEmpty ? (_map(urls.first)?['url'] as String?) : null);
          final entry = ImportNormalizer.build(
            name: overview['title'] as String?,
            username: username,
            password: password,
            url: url,
            notes: details['notesPlain'] as String?,
            rawTotp: _onePasswordTotp(details),
            folder: vaultName,
          );
          if (entry == null) {
            skipped++;
          } else {
            entries.add(entry);
          }
        }
      }
    }
    return ParsedFile(
      format: ImportFormat.onePassword1pux,
      entries: entries,
      skippedCount: skipped,
    );
  }

  /// Palladin's own JSON export — `{ vaults: [{ entries: [...] }] }`.
  static ParsedFile parsePalladin(Map<String, dynamic> root) {
    final entries = <ParsedEntry>[];
    var skipped = 0;
    for (final vaultRaw in _list(root['vaults'])) {
      final vault = _map(vaultRaw);
      final vaultName = vault?['name'] as String?;
      for (final entryRaw in _list(vault?['entries'])) {
        final e = _map(entryRaw);
        if (e == null) continue;
        final entry = ImportNormalizer.build(
          name: e['name'] as String?,
          username: e['username'] as String?,
          password: e['password'] as String?,
          url: e['urlDomain'] as String? ?? e['url'] as String?,
          notes: e['notes'] as String?,
          rawTotp: e['totp'] as String?,
          folder: vaultName,
        );
        if (entry == null) {
          skipped++;
        } else {
          entries.add(entry);
        }
      }
    }
    return ParsedFile(
      format: ImportFormat.palladinJson,
      entries: entries,
      skippedCount: skipped,
    );
  }

  /// Enpass JSON — `{ items: [{ title, fields: [{ type, value }] }] }` where
  /// login/password/url/totp are distinguished by `field.type`.
  static ParsedFile parseEnpass(Map<String, dynamic> root) {
    final entries = <ParsedEntry>[];
    var skipped = 0;
    for (final itemRaw in _list(root['items'])) {
      final item = _map(itemRaw);
      if (item == null) continue;
      final fields = _list(item['fields']);
      String? byType(String type) {
        for (final fRaw in fields) {
          final f = _map(fRaw);
          if (f?['type'] == type) {
            final value = f?['value'] as String?;
            if (value != null && value.trim().isNotEmpty) return value;
          }
        }
        return null;
      }

      final entry = ImportNormalizer.build(
        name: item['title'] as String?,
        username: byType('username') ?? byType('email'),
        password: byType('password'),
        url: byType('url'),
        notes: item['note'] as String?,
        rawTotp: byType('totp'),
      );
      if (entry == null) {
        skipped++;
      } else {
        entries.add(entry);
      }
    }
    return ParsedFile(
      format: ImportFormat.enpassJson,
      entries: entries,
      skippedCount: skipped,
    );
  }

  static Map<String, String> _bitwardenFolderNames(Map<String, dynamic> root) {
    final names = <String, String>{};
    for (final key in ['folders', 'collections']) {
      for (final raw in _list(root[key])) {
        final folder = _map(raw);
        final id = folder?['id'] as String?;
        final name = folder?['name'] as String?;
        if (id != null && name != null) names[id] = name;
      }
    }
    return names;
  }

  static String? _onePasswordTotp(Map<String, dynamic> details) {
    for (final sectionRaw in _list(details['sections'])) {
      final section = _map(sectionRaw);
      for (final fieldRaw in _list(section?['fields'])) {
        final field = _map(fieldRaw);
        final id = field?['id'] as String? ?? '';
        final value = field?['value'];
        if (value is String) {
          if (id.startsWith('TOTP_') ||
              value.toLowerCase().startsWith('otpauth://')) {
            return value;
          }
        } else if (value is Map) {
          final totp = value['totp'];
          if (totp is String && totp.isNotEmpty) return totp;
        }
      }
    }
    return null;
  }

  static String? _designation(List<dynamic> fields, String designation) {
    for (final raw in fields) {
      final field = _map(raw);
      if (field?['designation'] == designation) {
        final value = field?['value'] as String?;
        if (value != null && value.trim().isNotEmpty) return value;
      }
    }
    return null;
  }

  static String? _appendUris(String? notes, Iterable<String> extraUris) {
    if (extraUris.isEmpty) return notes;
    final extra = extraUris.join('\n');
    return notes == null || notes.isEmpty ? extra : '$notes\n$extra';
  }

  static List<dynamic> _list(dynamic value) =>
      value is List ? value : const <dynamic>[];

  static Map<String, dynamic>? _map(dynamic value) =>
      value is Map<String, dynamic> ? value : null;
}
