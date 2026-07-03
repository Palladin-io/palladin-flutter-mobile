import '../../domain/entities/entry_entity.dart';

/// A password-manager export format the import wizard can recognise and
/// map onto a Palladin entry.
///
/// The wire value ([id]) is what we send to the backend import endpoint
/// and record in analytics — keep it stable and hyphen-cased.
enum ImportFormat {
  genericCsv('generic-csv'),
  firefoxCsv('firefox-csv'),
  safariCsv('safari-csv'),
  bitwardenJson('bitwarden-json'),
  bitwardenCsv('bitwarden-csv'),
  lastpassCsv('lastpass-csv'),
  onePasswordCsv('1password-csv'),
  onePassword1pux('1password-1pux'),
  dashlaneCsv('dashlane-csv'),
  dashlaneZip('dashlane-zip'),
  keepassXml('keepass-xml'),
  nordpassCsv('nordpass-csv'),
  keeperJson('keeper-json'),
  protonPassJson('protonpass-json'),
  roboformCsv('roboform-csv'),
  palladinJson('palladin-json'),
  palladinCsv('palladin-csv'),

  /// The CSV could not be matched to a known profile — the user maps the
  /// columns manually before the entries are built.
  manualCsv('manual-csv');

  const ImportFormat(this.id);

  /// Stable wire identifier sent to the backend and analytics.
  final String id;
}

/// Why a source file could not be imported at all (as opposed to a file
/// that parses but yields zero login entries).
enum ImportUnsupportedReason {
  /// The file is empty or unreadable.
  empty,

  /// A ZIP/JSON/XML that we recognise as encrypted and therefore cannot
  /// parse client-side (e.g. `.kdbx`, a PGP-armored Proton export).
  encrypted,

  /// The bytes matched none of our parsers and are not a mappable CSV.
  unrecognised,
}

/// A single login entry extracted and normalised from a source file.
///
/// This is the intermediate representation between a manager-specific
/// parser and a Palladin [EntryEntity]. Every field is already trimmed
/// and normalised (TOTP wrapped in an `otpauth://` URI, [urlDomain]
/// reduced to a host). Secrets ([password], [totp]) live only in memory
/// and must never be logged.
class ParsedEntry {
  const ParsedEntry({
    required this.name,
    this.username,
    this.password,
    this.url,
    this.urlDomain,
    this.notes,
    this.totp,
    this.folder,
  });

  /// Display label (maps to [EntryEntity.label]).
  final String name;

  final String? username;
  final String? password;

  /// Full URL as it appeared in the source — stored inside the encrypted
  /// payload so nothing is lost on round-trip.
  final String? url;

  /// Host extracted from [url] — the plaintext meta line on the row.
  final String? urlDomain;

  final String? notes;

  /// `otpauth://` URI (bare secrets are wrapped during normalisation).
  final String? totp;

  /// Source folder / group / collection name — surfaced in the preview
  /// but not yet mapped to a Palladin vault.
  final String? folder;

  /// Builds the plaintext credential payload for on-device encryption.
  ///
  /// Every imported login becomes an [EntryType.credential]; the source
  /// managers export username/password logins, not standalone API keys.
  Map<String, dynamic> toPayload() {
    return CredentialPayload(
      username: username ?? '',
      password: password ?? '',
      url: url,
      notes: notes,
      totp: totp,
    ).toJson();
  }
}

/// Result of parsing a source file into login entries.
class ParsedFile {
  const ParsedFile({
    required this.format,
    required this.entries,
    this.skippedCount = 0,
  });

  final ImportFormat format;
  final List<ParsedEntry> entries;

  /// Non-login items (secure notes, cards, identities) that were dropped
  /// during parsing — surfaced so the user knows the count won't match
  /// the source manager's total.
  final int skippedCount;
}

/// A tabular CSV file split into a header row and data rows, used both by
/// the profile parsers and by the manual column mapper.
class CsvTable {
  const CsvTable({required this.headers, required this.rows});

  /// Header cells exactly as they appeared (original case preserved).
  final List<String> headers;

  /// Data rows — each is the full ordered list of cells for that line.
  final List<List<String>> rows;

  /// Header cells lower-cased and trimmed, for case-insensitive matching.
  List<String> get normalizedHeaders =>
      headers.map((h) => h.trim().toLowerCase()).toList(growable: false);
}

/// User-supplied mapping from CSV column indices to Palladin fields, used
/// when a CSV matches no known profile.
class ColumnMapping {
  const ColumnMapping({
    this.nameIndex,
    this.usernameIndex,
    this.passwordIndex,
    this.urlIndex,
    this.notesIndex,
    this.totpIndex,
  });

  final int? nameIndex;
  final int? usernameIndex;
  final int? passwordIndex;
  final int? urlIndex;
  final int? notesIndex;
  final int? totpIndex;

  /// At minimum a mapping needs a password column — without a secret
  /// there is nothing to import.
  bool get isUsable => passwordIndex != null;
}

/// Outcome of running the import engine over raw file bytes.
sealed class ImportOutcome {
  const ImportOutcome();
}

/// The file was parsed into login entries.
final class ImportParsed extends ImportOutcome {
  const ImportParsed(this.result);

  final ParsedFile result;
}

/// The file is a CSV that matched no profile — the UI must collect a
/// [ColumnMapping] and re-run parsing with it.
final class ImportNeedsMapping extends ImportOutcome {
  const ImportNeedsMapping(this.table);

  final CsvTable table;
}

/// The file cannot be imported (empty, encrypted, unrecognised).
final class ImportUnsupported extends ImportOutcome {
  const ImportUnsupported(this.reason);

  final ImportUnsupportedReason reason;
}
