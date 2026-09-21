import '../../../../core/utils/app_logger.dart';
import '../../../agents/domain/repositories/agents_repository.dart';
import '../../../grants/domain/entities/grant.dart';
import '../../../grants/domain/repositories/grants_repository.dart';
import '../../../vault/data/services/member_sync_service.dart';
import '../../../vault/domain/entities/entry_entity.dart';
import '../../../vault/domain/entities/member_index_entry.dart';
import '../../../vault/domain/entities/vault_entity.dart';
import '../../../vault/domain/repositories/vault_members_repository.dart';
import '../../domain/entities/inbox_notification.dart';

/// Resolves zero-knowledge notification labels from the unlocked local index.
final class NotificationPresentationResolver {
  const NotificationPresentationResolver({
    required MemberIndexReader index,
    GrantsRepository? grants,
    AgentsRepository? agents,
    VaultMembersRepository? vaultMembers,
  }) : _index = index,
       _grants = grants,
       _agents = agents,
       _vaultMembers = vaultMembers;

  final MemberIndexReader _index;
  final GrantsRepository? _grants;
  final AgentsRepository? _agents;
  final VaultMembersRepository? _vaultMembers;

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
    final agentNames = await _agentNames();
    final memberNames = <String, Map<String, String>>{};
    final output = <InboxNotification>[];
    for (final item in items) {
      final metadata = _structural(item.metadata);
      final vaultId = _string(metadata, 'vaultId');
      final vault = vaultId == null ? null : vaults[vaultId];
      if (vault != null) {
        metadata['vaultName'] = vault.name;
        final grant = await _grantFor(item, metadata, vault.id);
        if (grant != null) {
          metadata['grantType'] = grant.scope.name;
          metadata['entryId'] = grant.entryId;
        }
        final entryId = _string(metadata, 'entryId');
        if (entryId != null) {
          final label = await _entryLabel(vault.id, entryId);
          if (label != null) metadata['entryLabel'] = label;
        }
        final agentId = _string(metadata, 'agentId');
        final agentName = agentId == null ? null : agentNames[agentId];
        if (agentName != null) metadata['agentName'] = agentName;

        if (grant != null) {
          final reason = grant.reason?.trim();
          if (reason != null && reason.isNotEmpty) metadata['reason'] = reason;
          final actorId = _actorId(item.type, grant);
          if (actorId != null) {
            final names = memberNames[vault.id] ??= await _memberNames(
              vault.id,
            );
            final actorName = names[actorId];
            if (actorName != null) metadata['actorName'] = actorName;
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

  /// Removes locally resolved names and decrypted free text on lock/logout.
  List<InboxNotification> redact(List<InboxNotification> items) =>
      _generic(items);

  Future<String?> _entryLabel(String vaultId, String entryId) async {
    try {
      await _index.waitForCurrent(vaultId);
      final matches = _index
          .entries(vaultId)
          .where(
            (entry) =>
                entry.entryId == entryId &&
                entry.state != MemberEntryState.deleted &&
                !entry.corrupt,
          )
          .toList(growable: false);
      return matches.length == 1 ? matches.single.memberLabel : null;
    } catch (_) {
      AppLogger.w('Notifications', 'Local Entry-label resolution failed');
      return null;
    }
  }

  Future<EntryEntity?> resolveEntry(String vaultId, String entryId) async {
    await _index.waitForCurrent(vaultId);
    final matches = _index
        .entries(vaultId)
        .where(
          (entry) =>
              entry.entryId == entryId &&
              entry.state != MemberEntryState.deleted &&
              !entry.corrupt,
        )
        .toList(growable: false);
    if (matches.length != 1) return null;
    final entry = matches.single;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return EntryEntity(
      id: entry.entryId,
      vaultId: vaultId,
      label: entry.memberLabel,
      icon: entry.iconReference,
      type: EntryTypeExtension.fromWire(entry.entryType),
      createdAt: epoch,
      updatedAt: epoch,
      lifecycleState: entry.state,
      currentRevision: entry.revision,
      currentKeyVersion: entry.currentKeyVersion,
    );
  }

  List<InboxNotification> _generic(List<InboxNotification> items) => items
      .map((item) {
        final metadata = _structural(item.metadata);
        for (final key in const [
          'vaultId',
          'entryId',
          'grantId',
          'agentId',
          'reason',
          'denyReason',
          'note',
        ]) {
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
      'reason',
      'denyReason',
    ]) {
      copy.remove(key);
    }
    return copy;
  }

  Future<Map<String, String>> _agentNames() async {
    final repository = _agents;
    if (repository == null) return const {};
    try {
      final agents = await repository.listAgents();
      return {
        for (final agent in agents)
          if (agent.name?.trim().isNotEmpty == true)
            agent.agentId: agent.name!.trim(),
      };
    } catch (_) {
      AppLogger.w('Notifications', 'Local agent-name resolution failed');
      return const {};
    }
  }

  Future<Map<String, String>> _memberNames(String vaultId) async {
    final repository = _vaultMembers;
    if (repository == null) return const {};
    try {
      final members = await repository.list(vaultId);
      return {
        for (final member in members)
          if (member.name?.trim().isNotEmpty == true)
            member.id: member.name!.trim(),
      };
    } catch (_) {
      AppLogger.w('Notifications', 'Local member-name resolution failed');
      return const {};
    }
  }

  Future<Grant?> _grantFor(
    InboxNotification item,
    Map<String, dynamic> metadata,
    String vaultId,
  ) async {
    if (!const {
      'grant_pending',
      'grant_approved',
      'grant_denied',
      'grant_revoked',
    }.contains(item.type)) {
      return null;
    }
    final repository = _grants;
    final grantId = _string(metadata, 'grantId');
    if (repository == null || grantId == null) return null;
    try {
      final grant = await repository.getGrant(vaultId, grantId);
      final entryId = _string(metadata, 'entryId');
      final agentId = _string(metadata, 'agentId');
      if (grant.id != grantId ||
          grant.vaultId != vaultId ||
          (entryId != null && grant.entryId != entryId) ||
          (agentId != null && grant.agentId != agentId)) {
        return null;
      }
      return grant;
    } catch (_) {
      AppLogger.w('Notifications', 'Grant presentation resolution failed');
      return null;
    }
  }

  String? _actorId(String type, Grant grant) => switch (type) {
    'grant_approved' => grant.createdBy,
    'grant_denied' => grant.deniedBy,
    'grant_revoked' => grant.revokedBy,
    _ => null,
  };

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
