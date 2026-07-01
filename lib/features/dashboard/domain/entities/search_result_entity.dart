/// The kind of object a global-search hit points to.
enum SearchResultType { agent, vault, entry }

/// One row in the dashboard global-search autocomplete.
///
/// A lightweight projection returned by `GET /api/search` — metadata only,
/// never any encrypted payload, so zero-knowledge is preserved. [vaultName]
/// is populated for [SearchResultType.entry] hits only; [icon] is the
/// backend icon-name string (nullable), mapped to a Material icon at the
/// presentation layer via `EntryVisuals`/`VaultVisuals`.
class SearchResultEntity {
  const SearchResultEntity({
    required this.type,
    required this.id,
    required this.name,
    this.vaultName,
    this.icon,
  });

  final SearchResultType type;
  final String id;
  final String name;

  /// The parent vault's display name — set for [SearchResultType.entry] only.
  final String? vaultName;

  /// Backend icon-name string (nullable). Resolved to an icon at the UI layer.
  final String? icon;
}
