final class EntryShareListItem {
  const EntryShareListItem({
    required this.shareId,
    required this.status,
    required this.expiresAt,
    required this.maximumReceipts,
    required this.deliveryCount,
    required this.firstDeliveredAt,
    required this.lastDeliveredAt,
    required this.firstConfirmedAt,
    required this.notifyOnFirstReceipt,
    required this.recipientMode,
    required this.recipientEmail,
    required this.protection,
    required this.sourceChanged,
  });
  final String shareId, status, recipientMode, protection;
  final String? recipientEmail;
  final DateTime? expiresAt,
      firstDeliveredAt,
      lastDeliveredAt,
      firstConfirmedAt;
  final int? maximumReceipts;
  final int deliveryCount;
  final bool notifyOnFirstReceipt, sourceChanged;

  bool get canRevoke =>
      const {'active', 'locked', 'suspended', 'consumed'}.contains(status);

  bool get canChangeProtection =>
      status == 'active' &&
      const {'none', 'password', 'pin'}.contains(protection);
}

final class EntrySharesPage {
  EntrySharesPage({
    required List<EntryShareListItem> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);
  final List<EntryShareListItem> items;
  final String? nextCursor;
}

typedef EntrySharingSession = ({
  String principalId,
  String organizationId,
  String authorizationGeneration,
  int keyGeneration,
});

enum EntrySharingFailure { load, loadMore, revoke, protection, unavailable }

final class EntrySharingRequestException implements Exception {
  const EntrySharingRequestException();
  @override
  String toString() => 'EntrySharingRequestException';
}
