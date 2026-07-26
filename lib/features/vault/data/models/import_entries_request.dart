import 'entry_model.dart';

/// One item in a bulk import request — mirrors the single-entry
/// `CreateEntryRequest` shape plus an (always empty for now) `grantEntries`
/// list. The mobile create flow does not send FULL-grant wrap material, so
/// the backend re-wraps grants server-side; we send an empty list.
class ImportEntryItem {
  const ImportEntryItem({
    required this.label,
    this.description,
    this.icon,
    required this.type,
    required this.content,
    this.urlDomain,
  });

  final String label;
  final String? description;
  final String? icon;
  final int type;
  final EntryContentModel content;
  final String? urlDomain;

  Map<String, dynamic> toJson() => {
    'label': label,
    if (description != null) 'description': description,
    if (icon != null) 'icon': icon,
    'type': type,
    'content': content.toJson(),
    if (urlDomain != null) 'urlDomain': urlDomain,
    'grantEntries': const <dynamic>[],
  };
}

/// Body for `POST /api/vaults/{vaultId}/entries/import`.
class ImportEntriesRequest {
  const ImportEntriesRequest({required this.format, required this.entries});

  /// Stable format id (e.g. `bitwarden-json`) for backend audit/analytics.
  final String format;
  final List<Object> entries;

  Map<String, dynamic> toJson() => {
    'format': format,
    'entries': entries
        .map((e) => e is ImportEntryItem ? e.toJson() : e)
        .toList(growable: false),
  };
}
