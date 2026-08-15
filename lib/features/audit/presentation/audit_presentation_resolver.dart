import '../../../core/utils/app_logger.dart';
import '../../agents/domain/repositories/agents_repository.dart';
import '../../agents/presentation/bloc/agents_cubit.dart';
import '../../vault/data/services/member_sync_service.dart';
import '../../vault/domain/entities/vault_entity.dart';
import '../../vault/domain/repositories/vault_members_repository.dart';
import '../../vault/presentation/cubit/vault_list_cubit.dart';
import '../domain/entities/audit_log_entry.dart';

final class AuditPresentationNames {
  const AuditPresentationNames({
    this.agents = const {},
    this.vaults = const {},
    this.entries = const {},
    this.members = const {},
  });

  final Map<String, String> agents;
  final Map<String, String> vaults;
  final Map<String, String> entries;
  final Map<String, String> members;

  AuditPresentationNames merge(AuditPresentationNames other) =>
      AuditPresentationNames(
        agents: {...agents, ...other.agents},
        vaults: {...vaults, ...other.vaults},
        entries: {...entries, ...other.entries},
        members: {...members, ...other.members},
      );
}

/// Resolves audit presentation text exclusively from the unlocked, current
/// organization state. Server-supplied labels are never trusted here.
abstract interface class AuditPresentationResolver {
  Future<AuditPresentationNames> resolveNames(
    List<AuditLogEntry> page, {
    String? scopedVaultId,
  });

  Future<AuditPresentationNames> resolveEntryNames(
    List<AuditLogEntry> page, {
    required String scopedVaultId,
  });

  List<AuditLogEntry> applyNames(
    List<AuditLogEntry> page,
    AuditPresentationNames names,
  );
}

final class LocalAuditPresentationResolver
    implements AuditPresentationResolver {
  const LocalAuditPresentationResolver({
    required AgentsRepository agentsRepository,
    AgentsCubit? agentsCubit,
    required VaultListCubit vaultListCubit,
    required VaultMembersRepository vaultMembersRepository,
    required MemberIndexReader memberIndex,
  }) : _agentsRepository = agentsRepository,
       _agentsCubit = agentsCubit,
       _vaultListCubit = vaultListCubit,
       _vaultMembersRepository = vaultMembersRepository,
       _memberIndex = memberIndex;

  final AgentsRepository _agentsRepository;
  final AgentsCubit? _agentsCubit;
  final VaultListCubit _vaultListCubit;
  final VaultMembersRepository _vaultMembersRepository;
  final MemberIndexReader _memberIndex;

  @override
  Future<AuditPresentationNames> resolveNames(
    List<AuditLogEntry> page, {
    String? scopedVaultId,
  }) async {
    if (page.isEmpty) return const AuditPresentationNames();
    final requestedAgentIds = page
        .map((entry) => entry.agentId)
        .whereType<String>()
        .toSet();
    final agents = await _resolveAgentNames(requestedAgentIds);
    final vaults = _resolveVaultNames();
    final scopedAgents = Map.fromEntries(
      agents.entries.where((entry) => requestedAgentIds.contains(entry.key)),
    );
    final requestedVaultIds = page
        .map((entry) => entry.vaultId)
        .whereType<String>()
        .toSet();
    final allowedVaultIds = scopedVaultId != null
        ? {scopedVaultId}
        : requestedVaultIds.intersection(vaults.keys.toSet());
    final scopedVaults = Map.fromEntries(
      vaults.entries.where((entry) => allowedVaultIds.contains(entry.key)),
    );
    final entries = <String, String>{};
    final members = <String, String>{};
    for (final vaultId in allowedVaultIds) {
      final requestedEntryIds = page
          .where((entry) => entry.vaultId == vaultId)
          .map((entry) => entry.entryId)
          .whereType<String>()
          .toSet();
      if (requestedEntryIds.isNotEmpty) {
        entries.addAll(await _resolveEntryNames(vaultId, requestedEntryIds));
      }
      final requestedMemberIds = page
          .where((entry) => entry.vaultId == vaultId)
          .map((entry) => entry.userId)
          .whereType<String>()
          .toSet();
      if (requestedMemberIds.isNotEmpty) {
        try {
          final directory = await _vaultMembersRepository.list(vaultId);
          for (final member in directory) {
            final name = member.name?.trim();
            if (requestedMemberIds.contains(member.id) &&
                name != null &&
                name.isNotEmpty) {
              members[member.id] = name;
            }
          }
        } catch (_) {
          AppLogger.w('Audit', 'Local member-name resolution failed');
        }
      }
    }
    return AuditPresentationNames(
      agents: scopedAgents,
      vaults: scopedVaults,
      entries: entries,
      members: members,
    );
  }

  @override
  Future<AuditPresentationNames> resolveEntryNames(
    List<AuditLogEntry> page, {
    required String scopedVaultId,
  }) async {
    final requestedEntryIds = page
        .where((entry) => entry.vaultId == scopedVaultId)
        .map((entry) => entry.entryId)
        .whereType<String>()
        .toSet();
    if (requestedEntryIds.isEmpty) return const AuditPresentationNames();
    return AuditPresentationNames(
      entries: await _resolveEntryNames(scopedVaultId, requestedEntryIds),
    );
  }

  @override
  List<AuditLogEntry> applyNames(
    List<AuditLogEntry> page,
    AuditPresentationNames names,
  ) => page
      .map((entry) {
        final entryName = entry.entryId == null
            ? null
            : names.entries[entry.entryId];
        final vaultName = entry.vaultId == null
            ? null
            : names.vaults[entry.vaultId];
        final agentName = entry.agentId == null
            ? null
            : names.agents[entry.agentId];
        final memberName = entry.userId == null
            ? null
            : names.members[entry.userId];
        return AuditLogEntry(
          id: entry.id,
          eventType: entry.eventType,
          rawEventType: entry.rawEventType,
          actorType: entry.actorType,
          result: entry.result,
          occurredAt: entry.occurredAt,
          createdAt: entry.createdAt,
          userId: entry.userId,
          agentId: entry.agentId,
          agentName: agentName,
          actorName: memberName,
          vaultId: entry.vaultId,
          entryId: entry.entryId,
          entryLabel: entryName,
          // A Vault name must never masquerade as an unresolved Entry label.
          resolvedObjectName: entry.entryId == null ? vaultName : entryName,
          resolvedVaultName: vaultName,
          localPresentationOnly: true,
          metadata: entry.metadata,
        );
      })
      .toList(growable: false);

  Future<Map<String, String>> _resolveAgentNames(
    Set<String> requestedAgentIds,
  ) async {
    if (requestedAgentIds.isEmpty) return const {};
    try {
      final cubit = _agentsCubit;
      if (cubit != null) {
        if (cubit.state.status != AgentsStatus.loaded) {
          await cubit.refresh();
        } else {
          await cubit.waitForCurrent();
        }
      }
      final agents =
          cubit?.state.agents ?? await _agentsRepository.listAgents();
      return {
        for (final agent in agents)
          if (requestedAgentIds.contains(agent.agentId) &&
              agent.name != null &&
              agent.name!.trim().isNotEmpty)
            agent.agentId: agent.name!.trim(),
      };
    } catch (_) {
      AppLogger.w('Audit', 'Local agent-name resolution failed');
      return const {};
    }
  }

  Future<Map<String, String>> _resolveEntryNames(
    String vaultId,
    Set<String> requestedEntryIds,
  ) async {
    try {
      await _memberIndex.waitForCurrent(vaultId);
      return {
        for (final entry in _memberIndex.entries(vaultId))
          if (!entry.corrupt && requestedEntryIds.contains(entry.entryId))
            entry.entryId: entry.memberLabel,
      };
    } catch (_) {
      AppLogger.w('Audit', 'Local entry-name resolution failed');
      return const {};
    }
  }

  Map<String, String> _resolveVaultNames() {
    try {
      final vaults = switch (_vaultListCubit.state) {
        VaultListLoaded(:final vaults) => vaults,
        _ => const <VaultEntity>[],
      };
      return {for (final vault in vaults) vault.id: vault.name};
    } catch (_) {
      AppLogger.w('Audit', 'Local vault-name resolution failed');
      return const {};
    }
  }
}
