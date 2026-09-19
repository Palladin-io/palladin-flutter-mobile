/// The kind of object a global-search hit points to.
enum SearchResultType { agent, member, vault, entry, unknown }

/// Discriminated global-search identity.
///
/// Each subtype carries only the scope required for safe navigation. Vault
/// and Entry presentation is produced locally; Agent and Member presentation
/// comes from the authorization-scoped administrative catalog.
sealed class SearchResultEntity {
  const SearchResultEntity();

  SearchResultType get type;
  String get id;
  String get name;
  String? get icon;

  String get deduplicationKey;
}

final class AgentSearchResult extends SearchResultEntity {
  const AgentSearchResult({required this.agentId, required this.displayName});

  final String agentId;
  final String displayName;

  @override
  SearchResultType get type => SearchResultType.agent;
  @override
  String get id => agentId;
  @override
  String get name => displayName;
  @override
  String? get icon => null;
  @override
  String get deduplicationKey => 'agent:$agentId';
}

final class MemberSearchResult extends SearchResultEntity {
  const MemberSearchResult({required this.memberId, required this.displayName});

  final String memberId;
  final String displayName;

  @override
  SearchResultType get type => SearchResultType.member;
  @override
  String get id => memberId;
  @override
  String get name => displayName;
  @override
  String? get icon => null;
  @override
  String get deduplicationKey => 'member:$memberId';
}

final class VaultSearchResult extends SearchResultEntity {
  const VaultSearchResult({
    required this.vaultId,
    required this.displayName,
    this.iconReference,
  });

  final String vaultId;
  final String displayName;
  final String? iconReference;

  @override
  SearchResultType get type => SearchResultType.vault;
  @override
  String get id => vaultId;
  @override
  String get name => displayName;
  @override
  String? get icon => iconReference;
  @override
  String get deduplicationKey => 'vault:$vaultId';
}

final class EntrySearchResult extends SearchResultEntity {
  const EntrySearchResult({
    required this.vaultId,
    required this.entryId,
    required this.displayName,
    required this.vaultName,
    required this.entryType,
    required this.currentRevision,
    required this.currentKeyVersion,
    this.iconReference,
  });

  final String vaultId;
  final String entryId;
  final String displayName;
  final String vaultName;
  final int entryType;
  final String currentRevision;
  final int currentKeyVersion;
  final String? iconReference;

  @override
  SearchResultType get type => SearchResultType.entry;
  @override
  String get id => entryId;
  @override
  String get name => displayName;
  @override
  String? get icon => iconReference;
  @override
  String get deduplicationKey => 'entry:$vaultId:$entryId';
}

/// Display-only forward-compatible hit; never treated as a known target.
final class UnknownSearchResult extends SearchResultEntity {
  const UnknownSearchResult({
    required this.rawType,
    required this.id,
    required this.name,
  });
  final String rawType;
  @override
  final String id;
  @override
  final String name;
  @override
  SearchResultType get type => SearchResultType.unknown;
  @override
  String? get icon => null;
  @override
  String get deduplicationKey => '$rawType:$id';
}
