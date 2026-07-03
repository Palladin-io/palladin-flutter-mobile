import 'package:xml/xml.dart';

import 'import_models.dart';
import 'import_normalizer.dart';

/// Parser for the KeePass 2.x "Export → KeePass XML" format.
///
/// Structure: `<KeePassFile><Root><Group>…</Group></Root></KeePassFile>`
/// with nested `<Group>`s and `<Entry>`s. Each entry is a list of
/// `<String><Key>…</Key><Value>…</Value></String>` pairs. Standard keys
/// are `Title`, `UserName`, `Password`, `URL`, `Notes`; TOTP hides under
/// several non-standard keys checked in order.
class ImportXmlParser {
  ImportXmlParser._();

  static const _totpKeys = ['otp', 'totp seed', 'timeotp-secret-base32', 'totp'];

  /// Parses a KeePass XML [document] into login entries. The group path is
  /// joined with `/` and surfaced as the folder.
  static ParsedFile parse(XmlDocument document) {
    final entries = <ParsedEntry>[];
    var skipped = 0;

    final root = document.rootElement;
    for (final group in root.findElements('Root')) {
      _walkGroups(group, const [], entries, (n) => skipped += n);
    }
    return ParsedFile(
      format: ImportFormat.keepassXml,
      entries: entries,
      skippedCount: skipped,
    );
  }

  static void _walkGroups(
    XmlElement node,
    List<String> path,
    List<ParsedEntry> out,
    void Function(int) onSkip,
  ) {
    for (final group in node.findElements('Group')) {
      final name = group.getElement('Name')?.innerText.trim() ?? '';
      final childPath = name.isEmpty ? path : [...path, name];
      for (final entryEl in group.findElements('Entry')) {
        final entry = _parseEntry(entryEl, childPath);
        if (entry == null) {
          onSkip(1);
        } else {
          out.add(entry);
        }
      }
      _walkGroups(group, childPath, out, onSkip);
    }
  }

  static ParsedEntry? _parseEntry(XmlElement entryEl, List<String> path) {
    final fields = <String, String>{};
    for (final str in entryEl.findElements('String')) {
      final key = str.getElement('Key')?.innerText.trim();
      final value = str.getElement('Value')?.innerText;
      if (key != null && value != null) fields[key.toLowerCase()] = value;
    }
    String? totp;
    for (final key in _totpKeys) {
      final value = fields[key];
      if (value != null && value.trim().isNotEmpty) {
        totp = value;
        break;
      }
    }
    return ImportNormalizer.build(
      name: fields['title'],
      username: fields['username'],
      password: fields['password'],
      url: fields['url'],
      notes: fields['notes'],
      rawTotp: totp,
      folder: path.isEmpty ? null : path.join('/'),
    );
  }
}
