/// The kind of object a global-search hit points to.
enum SearchResultType { agent, member, vault, entry }

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
  const AgentSearchResult({
    required this.organizationId,
    required this.agentId,
    required this.displayName,
    this.iconReference,
  });

  final String organizationId;
  final String agentId;
  final String displayName;
  final String? iconReference;

  @override
  SearchResultType get type => SearchResultType.agent;
  @override
  String get id => agentId;
  @override
  String get name => displayName;
  @override
  String? get icon => iconReference;
  @override
  String get deduplicationKey => 'agent:$organizationId:$agentId';
}

final class MemberSearchResult extends SearchResultEntity {
  const MemberSearchResult({
    required this.organizationId,
    required this.memberId,
    required this.displayName,
    this.iconReference,
  });

  final String organizationId;
  final String memberId;
  final String displayName;
  final String? iconReference;

  @override
  SearchResultType get type => SearchResultType.member;
  @override
  String get id => memberId;
  @override
  String get name => displayName;
  @override
  String? get icon => iconReference;
  @override
  String get deduplicationKey => 'member:$organizationId:$memberId';
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
    this.iconReference,
  });

  final String vaultId;
  final String entryId;
  final String displayName;
  final String vaultName;
  final int entryType;
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
