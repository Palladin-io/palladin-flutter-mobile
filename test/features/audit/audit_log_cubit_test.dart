import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/agents/domain/entities/agent.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/domain/exceptions/audit_exceptions.dart';
import 'package:mobile_palladin/features/audit/domain/repositories/audit_repository.dart';
import 'package:mobile_palladin/features/audit/presentation/cubit/audit_log_cubit.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_repository.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';

class _MockAuditRepository extends Mock implements AuditRepository {}

class _MockAgentsRepository extends Mock implements AgentsRepository {}

class _MockVaultRepository extends Mock implements VaultRepository {}

class _MockMemberIndex extends Mock implements MemberIndexReader {}

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
  late VaultRepository vaults;
  late MemberIndexReader memberIndex;

  setUp(() {
    audit = _MockAuditRepository();
    agents = _MockAgentsRepository();
    vaults = _MockVaultRepository();
    memberIndex = _MockMemberIndex();
    when(() => memberIndex.waitForCurrent(any())).thenAnswer((_) async {});
    when(() => memberIndex.entries(any())).thenReturn(const []);
    when(() => vaults.listVaults()).thenAnswer((_) async => const []);
  });

  AuditLogCubit vaultCubit() => AuditLogCubit(
    auditRepository: audit,
    agentsRepository: agents,
    vaultRepository: vaults,
    memberSync: memberIndex,
    scope: AuditLogScope.vault,
    vaultId: 'v-1',
  );

  AuditLogCubit orgCubit() => AuditLogCubit(
    auditRepository: audit,
    agentsRepository: agents,
    vaultRepository: vaults,
    memberSync: memberIndex,
    scope: AuditLogScope.org,
    vaultId: null,
  );

  group('vault scope', () {
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
        when(
          () => vaults.listVaults(),
        ).thenAnswer((_) async => [_vault('v-1', 'Production')]);
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
  });

  group('org scope', () {
    test('load() calls the org endpoint and resolves vault names', () async {
      when(() => agents.listAgents()).thenAnswer((_) async => []);
      when(
        () => vaults.listVaults(),
      ).thenAnswer((_) async => [_vault('v-1', 'Production')]);
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
      when(() => vaults.listVaults()).thenAnswer((_) async => []);
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
      when(() => vaults.listVaults()).thenAnswer((_) async => []);
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
