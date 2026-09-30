import 'inbox_notification.dart';

typedef EntrySharingNotificationTarget = ({String vaultId, String entryId});

EntrySharingNotificationTarget? entrySharingNotificationTarget(
  InboxNotification item,
) {
  if (item.type != 'entry_share_received') return null;
  final vaultId = item.metadata['vaultId'];
  final entryId = item.metadata['entryId'];
  if (vaultId is! String ||
      vaultId.isEmpty ||
      entryId is! String ||
      entryId.isEmpty) {
    return null;
  }
  return (vaultId: vaultId, entryId: entryId);
}
