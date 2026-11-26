// Offline, synthetic data boundaries for the production mobile UI preview.
import 'dart:typed_data';
import 'vault_adapters.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_presentation_resolver.dart';
import 'package:mobile_palladin/features/audit/presentation/cubit/entry_logs_cubit.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_members_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/agents/domain/entities/agent.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/approval/domain/repositories/approval_repository.dart';
import 'package:mobile_palladin/features/approval/data/services/grant_approval_review_service.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/grant_approval_cubit.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/grants/domain/repositories/grants_repository.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/notification_preference.dart';
import 'package:mobile_palladin/features/notifications/domain/repositories/notification_center_repository.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/notification_center_cubit.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/domain/repositories/audit_repository.dart';
import 'package:mobile_palladin/features/audit/presentation/audit_presentation_resolver.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';

final activityPreview = ActivityPreviewStore();

void registerActivityPreview() {
  getIt.allowReassignment = true;
  getIt.registerSingleton<NotificationPresentationResolver>(
    NotificationPresentationResolver(
      index: vaultPreview,
      grants: activityPreview,
      agents: activityPreview,
    ),
  );
  getIt.registerFactoryParam<EntryLogsCubit, String, String>(
    (vaultId, entryId) => EntryLogsCubit(
      auditRepository: activityPreview,
      agentsRepository: activityPreview,
      vaultListCubit: getIt<VaultListCubit>(),
      vaultMembersRepository: getIt<VaultMembersRepository>(),
      memberSync: vaultPreview,
      vaultId: vaultId,
      entryId: entryId,
    ),
  );
  getIt.registerSingleton<AgentsRepository>(activityPreview);
  getIt.registerSingleton<GrantsRepository>(activityPreview);
  getIt.registerSingleton<ApprovalRepository>(activityPreview);
  getIt.registerSingleton<NotificationCenterRepository>(activityPreview);
  getIt.registerSingleton<AuditRepository>(activityPreview);
  getIt.registerSingleton<AuditPresentationResolver>(PreviewAuditNames());
  getIt.registerLazySingleton<NotificationCenterCubit>(
    () => NotificationCenterCubit(repository: activityPreview),
  );
  getIt.registerFactoryParam<GrantApprovalCubit, PendingGrant, void>(
    (grant, _) => GrantApprovalCubit(
      repository: activityPreview,
      reviewService: PreviewApprovalReviewer(),
      grant: grant,
    ),
  );
}

class ActivityPreviewStore
    implements
        AgentsRepository,
        GrantsRepository,
        ApprovalRepository,
        NotificationCenterRepository,
        AuditRepository {
  final agents = <Agent>[
    Agent(
      agentId: 'agent-claude',
      name: 'Claude Code',
      type: 'claudeCode',
      description: 'Development assistant for the Palladin workspace',
      status: AgentStatus.active,
      publicKeyPrefix: 'DEMOCLAD',
      publicKeySuffix: 'A12345',
      publicKey: 'synthetic-public-key-claude',
      createdAt: DateTime.now().subtract(const Duration(days: 12)),
      enrolledAt: DateTime.now().subtract(const Duration(days: 12)),
      enrolledByName: 'Alex Morgan',
      lastAccessAt: DateTime.now().subtract(const Duration(minutes: 8)),
      lastHostname: 'studio-mac',
      lastIp: '192.0.2.14',
    ),
    Agent(
      agentId: 'agent-codex',
      name: 'Codex',
      type: 'other',
      description: 'Code review and maintenance',
      status: AgentStatus.active,
      publicKeyPrefix: 'DEMOCODX',
      publicKeySuffix: 'B12345',
      publicKey: 'synthetic-public-key-codex',
      createdAt: DateTime.now().subtract(const Duration(days: 6)),
      lastHostname: 'workstation',
    ),
    Agent(
      agentId: 'agent-reviewer',
      name: 'Review assistant',
      type: 'other',
      status: AgentStatus.pending,
      publicKeyPrefix: 'DEMOREVW',
      publicKeySuffix: 'C12345',
      createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
    ),
  ];
  final grants = <Grant>[];
  final pending = <PendingGrant>[];
  final notifications = <InboxNotification>[];
  final logs = <AuditLogEntry>[];
  final preferenceRows = <NotificationPreference>[];

  ActivityPreviewStore() {
    for (var i = 0; i < 2; i++) {
      final entry = i == 0 ? 'entry-github' : 'entry-notion';
      final agent = i == 0 ? 'agent-claude' : 'agent-codex';
      final id = 'request-${i + 1}';
      pending.add(
        PendingGrant(
          grantId: id,
          vaultId: 'vault-work',
          agentId: agent,
          entryId: entry,
          agentPublicKey: 'synthetic-public-key',
          encryptedReason: null,
          agentName: i == 0 ? 'Claude Code' : 'Codex',
          vaultName: 'Work',
          entryLabel: entryNames[entry],
          createdAt: DateTime.now().subtract(Duration(minutes: 5 + i * 8)),
          requestedMethods: const [GrantMethod.inject],
          recipientAgentKeyVersion: 1,
        ),
      );
      _addGrant(
        id: id,
        vaultId: 'vault-work',
        agentId: agent,
        entryId: entry,
        scope: GrantScope.granular,
        status: GrantStatus.pending,
      );
      _notify(
        'grant_pending',
        id,
        agentId: agent,
        entryId: entry,
        pending: true,
      );
    }
    _addGrant(
      id: 'grant-active',
      vaultId: 'vault-work',
      agentId: 'agent-claude',
      entryId: 'entry-github',
      scope: GrantScope.granular,
      status: GrantStatus.active,
    );
    _addGrant(
      id: 'grant-expired',
      vaultId: 'vault-personal',
      agentId: 'agent-codex',
      entryId: 'entry-google',
      scope: GrantScope.granular,
      status: GrantStatus.expired,
    );
    _notify(
      'agent_pending',
      'agent-reviewer',
      agentId: 'agent-reviewer',
      pending: true,
    );
    _notify(
      'grant_approved',
      'grant-active',
      agentId: 'agent-claude',
      entryId: 'entry-github',
    );
    _notify(
      'grant_expired',
      'grant-expired',
      agentId: 'agent-codex',
      entryId: 'entry-google',
    );
    var historicalOffset = 0;
    for (final entry in entryNames.keys) {
      for (final type in [
        AuditEventType.credentialAccessed,
        AuditEventType.grantApproved,
        AuditEventType.grantExpired,
        AuditEventType.entryUpdated,
        AuditEventType.entryCreated,
      ]) {
        _log(
          type,
          entryId: entry,
          occurredAt: DateTime.now().subtract(
            Duration(minutes: historicalOffset++ * 35),
          ),
          vaultId: entry == 'entry-google' ? 'vault-personal' : 'vault-work',
        );
      }
    }
    for (final type in [
      'grant_pending',
      'agent_pending',
      'grant_approved',
      'grant_revoked',
      'grant_expired',
      'agent_approved',
      'credential_stale',
    ]) {
      preferenceRows.add(
        NotificationPreference(
          type: type,
          category: type.endsWith('pending') ? 'ActionRequired' : 'Update',
          inboxEnabled: true,
          signalREnabled: true,
          pushEnabled: true,
          mandatory: [
            'grant_pending',
            'agent_pending',
            'grant_revoked',
          ].contains(type),
        ),
      );
    }
  }

  static const entryNames = {
    'entry-github': 'GitHub',
    'entry-google': 'Google',
    'entry-notion': 'Notion',
    'entry-api': 'Production API',
  };
  static const vaultNames = {
    'vault-personal': 'Personal',
    'vault-work': 'Work',
  };
  String _agentName(String id) =>
      agents.firstWhere((a) => a.agentId == id).name ?? id;

  void _log(
    AuditEventType type, {
    String? entryId,
    String vaultId = 'vault-work',
    DateTime? occurredAt,
  }) {
    logs.insert(
      0,
      AuditLogEntry(
        id: 'audit-${logs.length + 1}',
        eventType: type,
        rawEventType: type.wire,
        actorType: type == AuditEventType.credentialAccessed
            ? AuditActorType.agent
            : AuditActorType.user,
        agentId: 'agent-claude',
        userId: 'demo-user',
        vaultId: vaultId,
        entryId: entryId,
        createdAt: occurredAt ?? DateTime.now(),
        result: AuditResult.succeeded,
        agentName: _agentName('agent-claude'),
        actorName: type == AuditEventType.credentialAccessed
            ? _agentName('agent-claude')
            : 'Alex Morgan',
        entryLabel: entryNames[entryId],
        resolvedObjectName: entryNames[entryId] ?? vaultNames[vaultId],
        resolvedVaultName: vaultNames[vaultId],
        localPresentationOnly: true,
        metadata: type == AuditEventType.grantApproved
            ? const {'method': 'inject'}
            : const {},
      ),
    );
    logs.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  }

  void _notify(
    String type,
    String subject, {
    required String agentId,
    String? entryId,
    bool pending = false,
  }) {
    final matchingGrants = grants.where((g) => g.id == subject);
    final grant = matchingGrants.isEmpty ? null : matchingGrants.first;
    notifications.insert(
      0,
      InboxNotification(
        id: 'notification-${notifications.length + 1}',
        subjectId: subject,
        type: type,
        titleKey: type,
        category: pending
            ? NotificationCategory.actionRequired
            : NotificationCategory.update,
        actionState: pending
            ? NotificationActionState.pending
            : NotificationActionState.none,
        occurredAt: DateTime.now().subtract(
          Duration(minutes: notifications.length * 9),
        ),
        metadata: {
          'agentId': agentId,
          'agentName': _agentName(agentId),
          'vaultId': entryId == 'entry-google'
              ? 'vault-personal'
              : 'vault-work',
          'vaultName': entryId == 'entry-google' ? 'Personal' : 'Work',
          'grantId': subject,
          'grantType': grant?.scope.name ?? 'granular',
          if (grant != null)
            'methods': grant.methods
                .map((method) => method.wireName)
                .join(', '),
          'entryId': ?entryId,
          if (entryId != null) 'entryLabel': entryNames[entryId],
          if (entryId != null && entryId != 'entry-api')
            'entryUsername': entryId == 'entry-notion'
                ? 'alex.work@example.test'
                : 'alex@example.test',
          'actorName': 'Alex Morgan',
          'reason': 'Sign in to complete the requested workspace task.',
          'host': 'studio-mac',
          'ip': '192.0.2.14',
          'keyHint': 'DEMOREVW…C12345',
        },
      ),
    );
  }

  void _resolve(String subject) {
    for (var i = 0; i < notifications.length; i++) {
      if (notifications[i].subjectId == subject) {
        notifications[i] = notifications[i].copyWith(
          actionState: NotificationActionState.resolved,
          markRead: true,
        );
      }
    }
  }

  void _addGrant({
    required String id,
    required String vaultId,
    required String agentId,
    String? entryId,
    required GrantScope scope,
    required GrantStatus status,
    GrantLimit limit = const GrantLifetime(),
    List<GrantMethod> methods = const [GrantMethod.inject],
  }) {
    grants.removeWhere((g) => g.id == id);
    grants.insert(
      0,
      Grant(
        id: id,
        vaultId: vaultId,
        agentId: agentId,
        agentName: _agentName(agentId),
        vaultName: vaultNames[vaultId],
        entryId: entryId,
        entryLabel: entryNames[entryId],
        scope: scope,
        status: status,
        createdAt: DateTime.now(),
        methods: methods,
        expiresAt: limit is GrantExpiry ? limit.expiresAt : null,
        queryLimit: limit is GrantUseLimit ? limit.maxUses : null,
        queryCount: 0,
        createdBy: 'demo-user',
        createdByName: 'Alex Morgan',
        approvedByName: 'Alex Morgan',
        reason: 'Complete the requested workspace task.',
        canRevoke: status == GrantStatus.active,
        canGrantAgain: status.isTerminal,
        recipientAgentKeyVersion: 1,
        agentAccessEpoch: 1,
      ),
    );
  }

  @override
  Future<List<Agent>> listAgents() async => List.of(agents);
  @override
  Future<Agent> getAgent(String agentId) async =>
      agents.firstWhere((a) => a.agentId == agentId);
  void _editAgent(
    String id, {
    AgentStatus? status,
    String? name,
    String? description,
    String? type,
    String? iconKey,
    String? iconColor,
  }) {
    final i = agents.indexWhere((a) => a.agentId == id);
    final a = agents[i];
    agents[i] = Agent(
      agentId: id,
      name: name ?? a.name,
      description: description ?? a.description,
      type: type ?? a.type,
      iconKey: iconKey ?? a.iconKey,
      iconColor: iconColor ?? a.iconColor,
      status: status ?? a.status,
      publicKeyPrefix: a.publicKeyPrefix,
      publicKeySuffix: a.publicKeySuffix,
      publicKey: a.publicKey,
      createdAt: a.createdAt,
      enrolledAt: a.enrolledAt,
      enrolledByName: a.enrolledByName,
      lastAccessAt: a.lastAccessAt,
      lastHostname: a.lastHostname,
      lastIp: a.lastIp,
    );
  }

  @override
  Future<void> approveAgent(
    String agentId, {
    String? name,
    String? type,
    String? iconKey,
    String? iconColor,
  }) async {
    _editAgent(
      agentId,
      status: AgentStatus.active,
      name: name,
      type: type,
      iconKey: iconKey,
      iconColor: iconColor,
    );
    _resolve(agentId);
    _notify('agent_approved', agentId, agentId: agentId);
    _log(AuditEventType.agentEnrolled);
  }

  @override
  Future<void> deactivateAgent(String agentId) async {
    _editAgent(agentId, status: AgentStatus.deactivated);
    for (final g in List.of(
      grants,
    ).where((g) => g.agentId == agentId && g.status == GrantStatus.active)) {
      await revokeGrant(g.vaultId, g.id);
    }
    _log(AuditEventType.agentBlocked);
  }

  @override
  Future<void> reactivateAgent(String agentId) async {
    _editAgent(agentId, status: AgentStatus.active);
    _log(AuditEventType.agentReactivated);
  }

  @override
  Future<void> updateAgent(
    String agentId, {
    String? name,
    String? description,
    String? type,
    String? iconKey,
    String? iconColor,
  }) async => _editAgent(
    agentId,
    name: name,
    description: description,
    type: type,
    iconKey: iconKey,
    iconColor: iconColor,
  );

  @override
  Future<GrantListPage> listGrants(
    String vaultId, {
    String? status,
    String? agentId,
    String? cursor,
    int pageSize = 50,
  }) => listOrgGrants(
    vaultId: vaultId,
    status: status,
    agentId: agentId,
    cursor: cursor,
    pageSize: pageSize,
  );
  @override
  Future<GrantListPage> listOrgGrants({
    String? status,
    String? agentId,
    String? vaultId,
    String? entryId,
    String? query,
    String? cursor,
    int pageSize = 50,
  }) async => GrantListPage(
    grants: grants
        .where(
          (g) =>
              (status == null || g.status.name == status) &&
              (agentId == null || g.agentId == agentId) &&
              (vaultId == null || g.vaultId == vaultId) &&
              (entryId == null ||
                  g.entryId == entryId ||
                  g.scope == GrantScope.full) &&
              (query == null ||
                  '${g.agentName} ${g.entryLabel} ${g.vaultName}'
                      .toLowerCase()
                      .contains(query.toLowerCase())),
        )
        .toList(),
  );
  @override
  Future<Grant> getGrant(String vaultId, String grantId) async =>
      grants.firstWhere((g) => g.vaultId == vaultId && g.id == grantId);
  @override
  Future<T> withPresentationReads<T>(
    Future<T> Function(GrantReader read) operation,
  ) => operation(getGrant);
  @override
  Future<void> revokeGrant(String vaultId, String grantId) async {
    final g = await getGrant(vaultId, grantId);
    _addGrant(
      id: g.id,
      vaultId: vaultId,
      agentId: g.agentId!,
      entryId: g.entryId,
      scope: g.scope,
      status: GrantStatus.revoked,
      methods: g.methods,
    );
    _notify('grant_revoked', g.id, agentId: g.agentId!, entryId: g.entryId);
    _log(AuditEventType.grantRevoked, vaultId: vaultId, entryId: g.entryId);
  }

  @override
  Future<List<PendingGrant>> listPendingGrants() async => List.of(pending);
  @override
  Future<void> approveGrant({
    required PendingGrant grant,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
    required List<String> fieldIds,
    required String reviewedEntryRevision,
  }) async {
    _addGrant(
      id: grant.grantId,
      vaultId: grant.vaultId,
      agentId: grant.agentId,
      entryId: grant.entryId,
      scope: GrantScope.granular,
      status: GrantStatus.active,
      limit: limit,
      methods: methods,
    );
    pending.removeWhere((g) => g.grantId == grant.grantId);
    _resolve(grant.grantId);
    _notify(
      'grant_approved',
      grant.grantId,
      agentId: grant.agentId,
      entryId: grant.entryId,
    );
    _log(
      AuditEventType.grantApproved,
      vaultId: grant.vaultId,
      entryId: grant.entryId,
    );
  }

  @override
  Future<void> denyGrant({required PendingGrant grant}) async {
    _addGrant(
      id: grant.grantId,
      vaultId: grant.vaultId,
      agentId: grant.agentId,
      entryId: grant.entryId,
      scope: GrantScope.granular,
      status: GrantStatus.denied,
    );
    pending.removeWhere((g) => g.grantId == grant.grantId);
    _resolve(grant.grantId);
    _notify(
      'grant_denied',
      grant.grantId,
      agentId: grant.agentId,
      entryId: grant.entryId,
    );
    _log(
      AuditEventType.grantDenied,
      vaultId: grant.vaultId,
      entryId: grant.entryId,
    );
  }

  @override
  Future<void> createFullGrant({
    required String vaultId,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) async => _create(vaultId, agentId, null, GrantScope.full, limit, methods);
  @override
  Future<void> createGranularGrant({
    required String vaultId,
    required String entryId,
    List<String>? selectedFieldIds,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) async =>
      _create(vaultId, agentId, entryId, GrantScope.granular, limit, methods);
  @override
  Future<void> createScriptExecutionGrant({
    required String vaultId,
    required String scriptEntryId,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
  }) async => _create(
    vaultId,
    agentId,
    scriptEntryId,
    GrantScope.scriptExecution,
    limit,
    [GrantMethod.exec],
  );
  void _create(
    String vault,
    String agent,
    String? entry,
    GrantScope scope,
    GrantLimit limit,
    List<GrantMethod> methods,
  ) {
    final id = 'grant-local-${grants.length + 1}';
    _addGrant(
      id: id,
      vaultId: vault,
      agentId: agent,
      entryId: entry,
      scope: scope,
      status: GrantStatus.active,
      limit: limit,
      methods: methods,
    );
    _notify('grant_approved', id, agentId: agent, entryId: entry);
    _log(AuditEventType.grantCreated, vaultId: vault, entryId: entry);
  }

  @override
  Future<NotificationPage> list({String? cursor}) async =>
      NotificationPage(items: List.of(notifications));
  @override
  Future<NotificationSummary> summary() async => NotificationSummary(
    unreadCount: notifications
        .where((n) => !n.isRead && !n.isCollapsedPending)
        .length,
    pendingActionCount: notifications.where((n) => n.isOpenAction).length,
  );
  @override
  Future<void> markRead(String id) async {
    final i = notifications.indexWhere((n) => n.id == id);
    notifications[i] = notifications[i].copyWith(markRead: true);
  }

  @override
  Future<void> markAllRead() async {
    for (var i = 0; i < notifications.length; i++) {
      notifications[i] = notifications[i].copyWith(markRead: true);
    }
  }

  @override
  Future<List<NotificationPreference>> preferences() async =>
      List.of(preferenceRows);
  @override
  Future<List<NotificationPreference>> updatePreference({
    required String type,
    bool? inboxEnabled,
    bool? signalREnabled,
    bool? pushEnabled,
  }) async {
    final i = preferenceRows.indexWhere((p) => p.type == type);
    final p = preferenceRows[i];
    preferenceRows[i] = p.copyWith(
      inboxEnabled: p.mandatory ? true : inboxEnabled,
      signalREnabled: p.mandatory ? true : signalREnabled,
      pushEnabled: pushEnabled,
    );
    return preferences();
  }

  @override
  Future<AuditLogPage> listVaultLogs(
    String vaultId, {
    List<String> actions = const [],
    String? agentId,
    String? userId,
    String? entryId,
    DateTime? from,
    DateTime? to,
    String? cursor,
    int pageSize = 50,
  }) => listOrgLogs(
    vaultId: vaultId,
    actions: actions,
    agentId: agentId,
    userId: userId,
    entryId: entryId,
    from: from,
    to: to,
  );
  @override
  Future<AuditLogPage> listOrgLogs({
    List<String> actions = const [],
    String? vaultId,
    String? agentId,
    String? userId,
    String? entryId,
    DateTime? from,
    DateTime? to,
    String? cursor,
    int pageSize = 50,
  }) async => AuditLogPage(
    entries: logs
        .where(
          (e) =>
              (vaultId == null || e.vaultId == vaultId) &&
              (entryId == null || e.entryId == entryId) &&
              (agentId == null || e.agentId == agentId) &&
              (userId == null || e.userId == userId) &&
              (actions.isEmpty || actions.contains(e.rawEventType)) &&
              (from == null || !e.occurredAt.isBefore(from)) &&
              (to == null || !e.occurredAt.isAfter(to)),
        )
        .toList(),
  );
}

class PreviewApprovalReviewer implements GrantApprovalReviewer {
  @override
  Future<GrantApprovalReview> open({
    required PendingGrant grant,
    required Uint8List memberPrivateKey,
  }) async => GrantApprovalReview(
    reason: 'Sign in to complete the requested workspace task.',
    entryLabel: grant.entryLabel ?? 'GitHub',
    entryRevision: '1',
    agentName: grant.agentName,
    fields: [
      const GrantableApprovalField(
        id: 'credential.username',
        label: 'Username',
        access: AgentFieldAccess.onGrantValue,
      ),
      const GrantableApprovalField(
        id: 'credential.password',
        label: 'Password',
        access: AgentFieldAccess.onGrantValue,
      ),
    ],
  );
}

class PreviewAuditNames implements AuditPresentationResolver {
  @override
  Future<AuditPresentationNames> resolveNames(
    List<AuditLogEntry> page, {
    String? scopedVaultId,
  }) async => AuditPresentationNames(
    agents: {
      for (final a in activityPreview.agents) a.agentId: a.name ?? a.agentId,
    },
    vaults: ActivityPreviewStore.vaultNames,
    entries: ActivityPreviewStore.entryNames,
    members: const {'demo-user': 'Alex Morgan'},
  );
  @override
  Future<AuditPresentationNames> resolveEntryNames(
    List<AuditLogEntry> page, {
    required String scopedVaultId,
  }) => resolveNames(page);
  @override
  List<AuditLogEntry> applyNames(
    List<AuditLogEntry> page,
    AuditPresentationNames names,
  ) => page;
}
