/// A single decrypted entry flattened for export. All secrets are in
/// plaintext here — instances live only for the duration of a share and
/// must never be logged.
class ExportRecord {
  const ExportRecord({
    required this.name,
    this.url,
    this.username,
    this.password,
    this.notes,
    this.totp,
    this.folder,
  });

  final String name;
  final String? url;
  final String? username;
  final String? password;
  final String? notes;
  final String? totp;

  /// Owning vault name — becomes the `folder` column / JSON grouping.
  final String? folder;
}

/// Export file format the user picks before sharing.
enum ExportFormat {
  csv('csv', 'text/csv'),
  json('json', 'application/json');

  const ExportFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}
