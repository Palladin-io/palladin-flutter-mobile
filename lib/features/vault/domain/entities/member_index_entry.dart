enum MemberEntryState { active, archived, deleted }

/// Decrypted, runtime-only projection used by local Vault search.
final class MemberIndexEntry {
  const MemberIndexEntry({
    required this.entryId,
    required this.entryType,
    required this.memberLabel,
    required this.searchFields,
    required this.revision,
    required this.state,
    this.autofillDomains = const [],
    this.iconReference,
    this.corrupt = false,
  });

  final String entryId;
  final int entryType;
  final String memberLabel;
  final List<String> searchFields;
  final String revision;
  final MemberEntryState state;

  /// Member-authorized origins eligible for exact-host system AutoFill.
  final List<String> autofillDomains;
  final String? iconReference;
  final bool corrupt;
}
