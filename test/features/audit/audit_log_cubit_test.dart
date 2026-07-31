import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/agents/domain/entities/agent.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/domain/exceptions/audit_exceptions.dart';
import 'package:mobile_palladin/features/audit/domain/repositories/audit_repository.dart';
import 'package:mobile_palladin/features/audit/presentation/audit_presentation_resolver.dart';
import 'package:mobile_palladin/features/audit/presentation/cubit/audit_log_cubit.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_member.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_members_repository.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';

class _MockAuditRepository extends Mock implements AuditRepository {}

class _MockAgentsRepository extends Mock implements AgentsRepository {}

class _MockVaultListCubit extends Mock implements VaultListCubit {
  VaultListState current = const VaultListLoaded([]);

  @override
  VaultListState get state => current;
}

class _MockMemberIndex extends Mock implements MemberIndexReader {}

class _MockVaultMembersRepository extends Mock
    implements VaultMembersRepository {}

AuditLogEntry _entry(String id, {String? agentId, String? vaultId}) {
  return AuditLogEntry(
    id: id,
    eventType: AuditEventType.credentialAccessed,
    rawEventType: 'credential.accessed',
    actorType: AuditActorType.agent,
    createdAt: DateTime(2026, 6, 1, 10),
    agentId: agentId,
    vaultId: vaultId,
  );
}

Agent _agent(String id, String name) {
  return Agent(
    agentId: id,
    name: name,
    status: AgentStatus.active,
    publicKeySuffix: 'abcd',
    createdAt: DateTime(2026, 1, 1),
  );
}

VaultEntity _vault(String id, String name) {
  return VaultEntity(
    id: id,
    name: name,
    grantMode: GrantMode.granular,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    entryCount: 0,
    activeGrantCount: 0,
    memberCount: 1,
  );
}

void main() {
  late AuditRepository audit;
  late AgentsRepository agents;
  late _MockVaultListCubit vaults;
  late MemberIndexReader memberIndex;
  late VaultMembersRepository vaultMembers;

  setUp(() {
    audit = _MockAuditRepository();
    agents = _MockAgentsRepository();
    vaults = _MockVaultListCubit();
    memberIndex = _MockMemberIndex();
    vaultMembers = _MockVaultMembersRepository();
    when(() => memberIndex.waitForCurrent(any())).thenAnswer((_) async {});
    when(() => memberIndex.entries(any())).thenReturn(const []);
    when(() => vaultMembers.list(any())).thenAnswer((_) async => const []);
  });

  AuditPresentationResolver presentationResolver() =>
      LocalAuditPresentationResolver(
        agentsRepository: agents,
        vaultListCubit: vaults,
        vaultMembersRepository: vaultMembers,
        memberIndex: memberIndex,
      );

  AuditLogCubit vaultCubit() => AuditLogCubit(
    auditRepository: audit,
    presentationResolver: presentationResolver(),
    scope: AuditLogScope.vault,
    vaultId: 'v-1',
    entryNameRefreshDelay: Duration.zero,
  );

  AuditLogCubit orgCubit() => AuditLogCubit(
    auditRepository: audit,
    presentationResolver: presentationResolver(),
    scope: AuditLogScope.org,
    vaultId: null,
    entryNameRefreshDelay: Duration.zero,
  );

  group('vault scope', () {
    test(
      'does not present the Vault name as an unresolved Entry name',
      () async {
        when(() => agents.listAgents()).thenAnswer((_) async => []);
        vaults.current = VaultListLoaded([_vault('v-1', 'Personal')]);
        when(
          () => audit.listVaultLogs(
            'v-1',
            actions: any(named: 'actions'),
            agentId: any(named: 'agentId'),
            userId: any(named: 'userId'),
            entryId: any(named: 'entryId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => AuditLogPage(
            entries: [
              AuditLogEntry(
                id: 'audit-1',
                eventType: AuditEventType.entryCreated,
                rawEventType: 'entry.created',
                actorType: AuditActorType.user,
                createdAt: DateTime(2026),
                vaultId: 'v-1',
                entryId: 'entry-unresolved',
              ),
            ],
          ),
        );

        final cubit = vaultCubit();
        await cubit.load();

        expect(cubit.state.entries.single.resolvedObjectName, isNull);
        expect(cubit.state.entries.single.resolvedVaultName, 'Personal');
        await cubit.close();
      },
    );

    test('load() calls the vault endpoint and exposes the page', () async {
      when(
        () => agents.listAgents(),
      ).thenAnswer((_) async => [_agent('a-1', 'claude')]);
      when(
        () => audit.listVaultLogs(
          'v-1',
          actions: any(named: 'actions'),
          agentId: any(named: 'agentId'),
          userId: any(named: 'userId'),
          entryId: any(named: 'entryId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => AuditLogPage(
          entries: [_entry('1', agentId: 'a-1', vaultId: 'v-1')],
          nextCursor: 'c1',
        ),
      );

      final cubit = vaultCubit();
      await cubit.load();

      expect(cubit.state.status, AuditLogStatus.loaded);
      expect(cubit.state.entries.single.id, '1');
      expect(cubit.state.agentNames['a-1'], 'claude');
      expect(cubit.state.nextCursor, 'c1');
      verifyNever(() => audit.listOrgLogs());
      await cubit.close();
    });

    test(
      'load() resolves Vault and Entry names only from local state',
      () async {
        when(() => agents.listAgents()).thenAnswer((_) async => []);
        vaults.current = VaultListLoaded([_vault('v-1', 'Production')]);
        when(() => memberIndex.entries('v-1')).thenReturn(const [
          MemberIndexEntry(
            entryId: 'e-1',
            entryType: 1,
            memberLabel: 'Stripe Key',
            searchFields: [],
            revision: 'r-1',
            state: MemberEntryState.active,
          ),
        ]);
        when(
          () => audit.listVaultLogs(
            'v-1',
            actions: any(named: 'actions'),
            agentId: any(named: 'agentId'),
            userId: any(named: 'userId'),
            entryId: any(named: 'entryId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => AuditLogPage(
            entries: [
              AuditLogEntry(
                id: '1',
                eventType: AuditEventType.entryUpdated,
                rawEventType: 'entry.updated',
                actorType: AuditActorType.user,
                createdAt: DateTime(2026),
                userId: 'user-opaque',
                vaultId: 'v-1',
                entryId: 'e-1',
                actorName: 'Server User',
                entryLabel: 'Server Entry',
              ),
            ],
          ),
        );

        final cubit = vaultCubit();
        await cubit.load();

        expect(cubit.state.entries.single.entryLabel, 'Stripe Key');
        expect(cubit.state.entries.single.actorName, isNull);
        expect(cubit.state.entries.single.resolvedObjectName, 'Stripe Key');
        expect(cubit.state.entries.single.localPresentationOnly, isTrue);
        verify(() => memberIndex.waitForCurrent('v-1')).called(1);
        await cubit.close();
      },
    );

    test(
      'refreshes unresolved Entry names when MemberIndex sync starts just after load',
      () async {
        when(() => agents.listAgents()).thenAnswer((_) async => []);
        vaults.current = VaultListLoaded([_vault('v-1', 'Production')]);
        var indexReady = false;
        var waitCalls = 0;
        when(() => memberIndex.waitForCurrent('v-1')).thenAnswer((_) async {
          waitCalls++;
          // The first lookup wins the race and observes no running sync. By
          // the delayed pass, synchronization has been registered/completed.
          if (waitCalls == 2) indexReady = true;
        });
        when(() => memberIndex.entries('v-1')).thenAnswer((_) {
          if (!indexReady) return const [];
          return const [
            MemberIndexEntry(
              entryId: 'e-1',
              entryType: 1,
              memberLabel: 'Stripe Key',
              searchFields: [],
              revision: 'r-1',
              state: MemberEntryState.active,
            ),
          ];
        });
        when(
          () => audit.listVaultLogs(
            'v-1',
            actions: any(named: 'actions'),
            agentId: any(named: 'agentId'),
            userId: any(named: 'userId'),
            entryId: any(named: 'entryId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => AuditLogPage(
            entries: [
              AuditLogEntry(
                id: '1',
                eventType: AuditEventType.entryCreated,
                rawEventType: 'entry.created',
                actorType: AuditActorType.user,
                createdAt: DateTime(2026),
                vaultId: 'v-1',
                entryId: 'e-1',
              ),
            ],
          ),
        );

        final cubit = AuditLogCubit(
          auditRepository: audit,
          presentationResolver: presentationResolver(),
          scope: AuditLogScope.vault,
          vaultId: 'v-1',
          entryNameRefreshDelay: const Duration(milliseconds: 1),
        );
        await cubit.load();

        expect(indexReady, isTrue);
        expect(cubit.state.entries.single.entryLabel, 'Stripe Key');
        expect(cubit.state.entries.single.resolvedObjectName, 'Stripe Key');
        verify(() => memberIndex.waitForCurrent('v-1')).called(2);
        await cubit.close();
      },
    );
  });

  group('org scope', () {
    test(
      'prefers scoped local names and preserves canonical metadata',
      () async {
        const vaultId = '11111111-1111-1111-1111-111111111111';
        when(
          () => agents.listAgents(),
        ).thenAnswer((_) async => [_agent('a-1', 'Local Agent')]);
        vaults.current = VaultListLoaded([_vault(vaultId, 'Local Vault')]);
        when(() => memberIndex.entries(vaultId)).thenReturn(const [
          MemberIndexEntry(
            entryId: 'e-1',
            entryType: 1,
            memberLabel: 'Local Entry',
            searchFields: [],
            revision: 'r',
            state: MemberEntryState.active,
          ),
        ]);
        when(() => vaultMembers.list(vaultId)).thenAnswer(
          (_) async => [
            VaultMember(
              id: 'u-1',
              name: 'Local Member',
              addedAt: DateTime(2026),
              status: VaultMemberStatus.active,
            ),
          ],
        );
        when(
          () => audit.listOrgLogs(
            actions: any(named: 'actions'),
            vaultId: any(named: 'vaultId'),
            agentId: any(named: 'agentId'),
            userId: any(named: 'userId'),
            entryId: any(named: 'entryId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => AuditLogPage(
            entries: [
              AuditLogEntry(
                id: 'log-1',
                eventType: AuditEventType.entryUpdated,
                rawEventType: 'entry.updated',
                actorType: AuditActorType.user,
                createdAt: DateTime(2026),
                userId: 'u-1',
                agentId: 'a-1',
                agentName: 'Hostile Agent',
                actorName: 'Hostile Member',
                vaultId: vaultId,
                entryId: 'e-1',
                entryLabel: 'Hostile Entry',
                agentReason: 'plaintext',
                metadata: const {'grantId': 'g-1'},
              ),
            ],
          ),
        );

        final cubit = orgCubit();
        await cubit.load();
        final row = cubit.state.entries.single;
        expect(row.agentName, 'Local Agent');
        expect(row.actorName, 'Local Member');
        expect(row.entryLabel, 'Local Entry');
        expect(row.resolvedVaultName, 'Local Vault');
        expect(row.agentReason, isNull);
        expect(row.metadata, {'grantId': 'g-1'});
        await cubit.close();
      },
    );

    test('does not resolve or query a vault outside the local scope', () async {
      const foreignVault = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      when(() => agents.listAgents()).thenAnswer((_) async => []);
      vaults.current = const VaultListLoaded([]);
      when(
        () => audit.listOrgLogs(
          actions: any(named: 'actions'),
          vaultId: any(named: 'vaultId'),
          agentId: any(named: 'agentId'),
          userId: any(named: 'userId'),
          entryId: any(named: 'entryId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async =>
            AuditLogPage(entries: [_entry('1', vaultId: foreignVault)]),
      );

      final cubit = orgCubit();
      await cubit.load();
      expect(cubit.state.vaultOptions.single.name, 'aaaaaaaa…eeeeee');
      verifyNever(() => memberIndex.waitForCurrent(foreignVault));
      verifyNever(() => vaultMembers.list(foreignVault));
      await cubit.close();
    });

    test('load() calls the org endpoint and resolves vault names', () async {
      when(() => agents.listAgents()).thenAnswer((_) async => []);
      vaults.current = VaultListLoaded([_vault('v-1', 'Production')]);
      when(
        () => audit.listOrgLogs(
          actions: any(named: 'actions'),
          vaultId: any(named: 'vaultId'),
          agentId: any(named: 'agentId'),
          userId: any(named: 'userId'),
          entryId: any(named: 'entryId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => AuditLogPage(
          entries: [_entry('1', vaultId: 'v-1')],
          nextCursor: null,
        ),
      );

      final cubit = orgCubit();
      await cubit.load();

      expect(cubit.state.status, AuditLogStatus.loaded);
      expect(cubit.state.vaultNames['v-1'], 'Production');
      expect(cubit.state.nextCursor, isNull);
      await cubit.close();
    });

    test('loadMore appends the next page and updates the cursor', () async {
      when(() => agents.listAgents()).thenAnswer((_) async => []);
      vaults.current = const VaultListLoaded([]);
      var call = 0;
      when(
        () => audit.listOrgLogs(
          actions: any(named: 'actions'),
          vaultId: any(named: 'vaultId'),
          agentId: any(named: 'agentId'),
          userId: any(named: 'userId'),
          entryId: any(named: 'entryId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) async {
        call++;
        return call == 1
            ? AuditLogPage(entries: [_entry('1')], nextCursor: 'c1')
            : AuditLogPage(entries: [_entry('2')], nextCursor: null);
      });

      final cubit = orgCubit();
      await cubit.load();
      await cubit.loadMore();

      expect(cubit.state.entries.map((e) => e.id), ['1', '2']);
      expect(cubit.state.nextCursor, isNull);
      await cubit.close();
    });

    test(
      'loadMore stops on a repeated cursor and respects the bound',
      () async {
        when(() => agents.listAgents()).thenAnswer((_) async => []);
        vaults.current = const VaultListLoaded([]);
        var call = 0;
        when(
          () => audit.listOrgLogs(
            actions: any(named: 'actions'),
            vaultId: any(named: 'vaultId'),
            agentId: any(named: 'agentId'),
            userId: any(named: 'userId'),
            entryId: any(named: 'entryId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer((_) async {
          call++;
          return call == 1
              ? AuditLogPage(entries: [_entry('1')], nextCursor: 'same')
              : AuditLogPage(
                  entries: [_entry('2'), _entry('3')],
                  nextCursor: 'same',
                );
        });
        final cubit = AuditLogCubit(
          auditRepository: audit,
          presentationResolver: presentationResolver(),
          scope: AuditLogScope.org,
          maximumLoadedEntries: 2,
        );
        await cubit.load();
        await cubit.loadMore();
        expect(cubit.state.entries.map((entry) => entry.id), ['1', '2']);
        expect(cubit.state.nextCursor, isNull);
        await cubit.loadMore();
        expect(call, 2);
        await cubit.close();
      },
    );
  });

  group('error handling', () {
    test('a typed AuditException surfaces its kind', () async {
      when(() => agents.listAgents()).thenAnswer((_) async => []);
      when(
        () => audit.listVaultLogs(
          'v-1',
          actions: any(named: 'actions'),
          agentId: any(named: 'agentId'),
          userId: any(named: 'userId'),
          entryId: any(named: 'entryId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenThrow(const AuditException(AuditErrorKind.forbidden));

      final cubit = vaultCubit();
      await cubit.load();

      expect(cubit.state.status, AuditLogStatus.error);
      expect(cubit.state.error, AuditErrorKind.forbidden);
      await cubit.close();
    });
  });

  group('client-side controls', () {
    test('applyFilter / search update state without refetch', () async {
      when(() => agents.listAgents()).thenAnswer((_) async => []);
      vaults.current = const VaultListLoaded([]);
      when(
        () => audit.listOrgLogs(
          actions: any(named: 'actions'),
          vaultId: any(named: 'vaultId'),
          agentId: any(named: 'agentId'),
          userId: any(named: 'userId'),
          entryId: any(named: 'entryId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) async => const AuditLogPage(entries: []));

      final cubit = orgCubit();
      await cubit.load();

      cubit.applyFilter(
        const AuditLogFilter(
          groups: {AuditEventGroup.grants},
          agentIds: {'a-9', 'a-8'},
          userIds: {'u-9'},
        ),
      );
      expect(cubit.state.groupFilters, {AuditEventGroup.grants});
      expect(cubit.state.agentFilters, {'a-9', 'a-8'});
      expect(cubit.state.userFilters, {'u-9'});

      cubit.applyFilter(const AuditLogFilter());
      expect(cubit.state.groupFilters, isEmpty);
      expect(cubit.state.agentFilters, isEmpty);
      expect(cubit.state.userFilters, isEmpty);

      cubit.search('hello');
      expect(cubit.state.query, 'hello');

      // Only the initial load hit the network.
      verify(
        () => audit.listOrgLogs(
          actions: any(named: 'actions'),
          vaultId: any(named: 'vaultId'),
          agentId: any(named: 'agentId'),
          userId: any(named: 'userId'),
          entryId: any(named: 'entryId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).called(1);
      await cubit.close();
    });
  });
}
