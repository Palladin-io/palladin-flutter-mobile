import '../../../vault/data/services/member_sync_service.dart';
import '../../../vault/domain/entities/member_index_entry.dart';
import '../../../vault/domain/entities/vault_entity.dart';
import '../../domain/entities/inbox_notification.dart';

/// Resolves zero-knowledge notification labels from the unlocked local index.
final class NotificationPresentationResolver {
  const NotificationPresentationResolver({required MemberIndexReader index})
    : _index = index;

  final MemberIndexReader _index;

  Future<List<InboxNotification>> resolve({
    required List<InboxNotification> items,
    required bool unlocked,
    required String activeAccountId,
    required String activeOrganizationId,
    required List<VaultEntity> activeVaults,
  }) async {
    if (!unlocked || activeAccountId.isEmpty || activeOrganizationId.isEmpty) {
      return _generic(items);
    }
    final vaults = {for (final vault in activeVaults) vault.id: vault};
    final output = <InboxNotification>[];
    for (final item in items) {
      final metadata = _structural(item.metadata);
      final vaultId = _string(metadata, 'vaultId');
      final vault = vaultId == null ? null : vaults[vaultId];
      if (vault != null) {
        metadata['vaultName'] = vault.name;
        final entryId = _string(metadata, 'entryId');
        if (entryId != null) {
          await _index.waitForCurrent(vault.id);
          final matches = _index
              .entries(vault.id)
              .where(
                (entry) =>
                    entry.entryId == entryId &&
                    entry.state != MemberEntryState.deleted &&
                    !entry.corrupt,
              )
              .toList(growable: false);
          if (matches.length == 1) {
            metadata['entryLabel'] = matches.single.memberLabel;
          }
        }
      } else {
        metadata.remove('vaultId');
        metadata.remove('entryId');
        metadata.remove('grantId');
      }
      output.add(_withMetadata(item, metadata));
    }
    return output;
  }

  List<InboxNotification> _generic(List<InboxNotification> items) => items
      .map((item) {
        final metadata = _structural(item.metadata);
        for (final key in const ['vaultId', 'entryId', 'grantId', 'agentId']) {
          metadata.remove(key);
        }
        return _withMetadata(item, metadata);
      })
      .toList(growable: false);

  Map<String, dynamic> _structural(Map<String, dynamic> source) {
    final copy = Map<String, dynamic>.from(source);
    for (final key in const [
      'vaultName',
      'entryLabel',
      'agentName',
      'actorName',
      'actionDeepLink',
    ]) {
      copy.remove(key);
    }
    return copy;
  }

  String? _string(Map<String, dynamic> source, String key) {
    final value = source[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  InboxNotification _withMetadata(
    InboxNotification item,
    Map<String, dynamic> metadata,
  ) => InboxNotification(
    id: item.id,
    subjectId: item.subjectId,
    type: item.type,
    category: item.category,
    titleKey: item.titleKey,
    metadata: metadata,
    actionState: item.actionState,
    occurredAt: item.occurredAt,
    readAt: item.readAt,
  );
}
