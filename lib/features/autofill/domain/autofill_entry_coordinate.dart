final class AutoFillEntryCoordinate {
  const AutoFillEntryCoordinate({required this.vaultId, required this.entryId});
  final String vaultId;
  final String entryId;
  @override
  bool operator ==(Object other) =>
      other is AutoFillEntryCoordinate &&
      other.vaultId == vaultId &&
      other.entryId == entryId;
  @override
  int get hashCode => Object.hash(vaultId, entryId);
}
