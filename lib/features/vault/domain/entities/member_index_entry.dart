/// Decrypted, runtime-only projection used by local Vault search.
final class MemberIndexEntry {
  const MemberIndexEntry({
    required this.entryId,
    required this.entryType,
    required this.memberLabel,
    required this.searchFields,
    required this.revision,
    this.iconReference,
  });

  final String entryId;
  final int entryType;
  final String memberLabel;
  final List<String> searchFields;
  final String revision;
  final String? iconReference;
}
