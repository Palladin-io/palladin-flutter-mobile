import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/agents/domain/entities/agent.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/domain/exceptions/audit_exceptions.dart';
import 'package:mobile_palladin/features/audit/domain/repositories/audit_repository.dart';
import 'package:mobile_palladin/features/audit/presentation/cubit/entry_logs_cubit.dart';
import 'package:mobile_palladin/features/audit/presentation/widgets/entry_logs_tab.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_member.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_members_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';

class _MockAuditRepository extends Mock implements AuditRepository {}

class _MockAgentsRepository extends Mock implements AgentsRepository {}

class _MockVaultListCubit extends Mock implements VaultListCubit {
  VaultListState current = VaultListLoaded([_vault()]);

  @override
  VaultListState get state => current;
}

class _MockMemberIndex extends Mock implements MemberIndexReader {}

class _MockVaultMembersRepository extends Mock
    implements VaultMembersRepository {}

AuditLogEntry _entry(String id, {String? agentId}) {
  return AuditLogEntry(
    id: id,
    eventType: AuditEventType.credentialAccessed,
    rawEventType: 'credential.accessed',
    actorType: AuditActorType.agent,
    createdAt: DateTime(2026, 6, 1, 10),
    agentId: agentId,
    vaultId: 'v-1',
    entryId: 'e-1',
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

void main() {
  late AuditRepository audit;
  late AgentsRepository agents;
  late _MockVaultListCubit vaults;
  late MemberIndexReader memberIndex;
  late VaultMembersRepository vaultMembers;
  late EntryLogsCubit cubit;

  setUp(() {
    audit = _MockAuditRepository();
    agents = _MockAgentsRepository();
    vaults = _MockVaultListCubit();
    memberIndex = _MockMemberIndex();
    vaultMembers = _MockVaultMembersRepository();
    when(() => memberIndex.waitForCurrent('v-1')).thenAnswer((_) async {});
    when(() => memberIndex.entries('v-1')).thenReturn([_memberEntry()]);
    when(() => vaultMembers.list('v-1')).thenAnswer((_) async => const []);
    cubit = EntryLogsCubit(
      auditRepository: audit,
      agentsRepository: agents,
      vaultListCubit: vaults,
      vaultMembersRepository: vaultMembers,
      memberSync: memberIndex,
      vaultId: 'v-1',
      entryId: 'e-1',
    );
  });

  tearDown(() => cubit.close());

  test(
    'loadMore failure surfaces loadMoreError and keeps existing entries',
    () async {
      when(() => agents.listAgents()).thenAnswer((_) async => []);
      when(
        () => audit.listVaultLogs(
          'v-1',
          entryId: 'e-1',
          cursor: null,
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => AuditLogPage(
          entries: [_entry('1', agentId: 'a-1')],
          nextCursor: 'c1',
        ),
      );
      await cubit.load();
      expect(cubit.state.entries, hasLength(1));
      expect(cubit.state.nextCursor, 'c1');

      when(
        () => audit.listVaultLogs(
          'v-1',
          entryId: 'e-1',
          cursor: 'c1',
          pageSize: any(named: 'pageSize'),
        ),
      ).thenThrow(const AuditException(AuditErrorKind.networkError));
      await cubit.loadMore();

      expect(cubit.state.loadMoreError, isTrue);
      expect(cubit.state.loadingMore, isFalse);
      expect(cubit.state.entries, hasLength(1)); // unchanged
      expect(cubit.state.nextCursor, 'c1'); // cursor preserved for retry
    },
  );

  test(
    'loadMore resolves the name of an agent first seen on a later page',
    () async {
      when(
        () => agents.listAgents(),
      ).thenAnswer((_) async => [_agent('a-1', 'Alpha')]);
      when(
        () => audit.listVaultLogs(
          'v-1',
          entryId: 'e-1',
          cursor: null,
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => AuditLogPage(
          entries: [_entry('1', agentId: 'a-1')],
          nextCursor: 'c1',
        ),
      );
      await cubit.load();
      expect(cubit.state.agentNames['a-1'], 'Alpha');

      // The next page introduces a-2 → the cache must be refreshed.
      when(() => agents.listAgents()).thenAnswer(
        (_) async => [_agent('a-1', 'Alpha'), _agent('a-2', 'Bravo')],
      );
      when(
        () => audit.listVaultLogs(
          'v-1',
          entryId: 'e-1',
          cursor: 'c1',
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => AuditLogPage(
          entries: [_entry('2', agentId: 'a-2')],
          nextCursor: null,
        ),
      );
      await cubit.loadMore();

      expect(cubit.state.agentNames['a-2'], 'Bravo');
      expect(cubit.state.entries, hasLength(2));
      verify(() => agents.listAgents()).called(2);
    },
  );

  test(
    'fetches by opaque vault and entry scope and resolves names locally',
    () async {
      when(
        () => agents.listAgents(),
      ).thenAnswer((_) async => [_agent('a-1', 'Local Agent')]);
      when(
        () => audit.listVaultLogs(
          'v-1',
          entryId: 'e-1',
          cursor: null,
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => AuditLogPage(
          entries: [
            AuditLogEntry(
              id: '1',
              eventType: AuditEventType.entryUpdated,
              rawEventType: 'entry.updated',
              actorType: AuditActorType.agent,
              createdAt: DateTime.utc(2026),
              vaultId: 'v-1',
              entryId: 'e-1',
              agentId: 'a-1',
              agentName: 'Server Agent',
              actorName: 'Server Actor',
              entryLabel: 'Server Entry',
              agentReason: 'server reason',
              metadata: const {'grantId': 'g-1', 'method': 'Get'},
            ),
          ],
        ),
      );

      await cubit.load();

      final resolved = cubit.state.entries.single;
      expect(resolved.agentName, 'Local Agent');
      expect(resolved.entryLabel, 'Local Entry');
      expect(resolved.resolvedVaultName, 'Local Vault');
      expect(resolved.actorName, 'Server Actor');
      expect(resolved.agentReason, isNull);
      expect(resolved.metadata, {'grantId': 'g-1', 'method': 'Get'});
      expect(resolved.localPresentationOnly, isTrue);
      verify(() => memberIndex.waitForCurrent('v-1')).called(1);
    },
  );

  test('resolves a user actor from the local Vault member directory', () async {
    when(() => agents.listAgents()).thenAnswer((_) async => []);
    when(() => vaultMembers.list('v-1')).thenAnswer(
      (_) async => [
        VaultMember(
          id: 'user-1',
          name: 'Patryk Roguszewski',
          addedAt: DateTime.utc(2026),
          status: VaultMemberStatus.active,
        ),
      ],
    );
    when(
      () => audit.listVaultLogs(
        'v-1',
        entryId: 'e-1',
        cursor: null,
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
            createdAt: DateTime.utc(2026),
            userId: 'user-1',
            actorName: 'untrusted server label',
            vaultId: 'v-1',
            entryId: 'e-1',
          ),
        ],
      ),
    );

    await cubit.load();

    expect(cubit.state.entries.single.actorName, 'Patryk Roguszewski');
  });

  test('rejects a response outside the requested composite scope', () async {
    when(() => agents.listAgents()).thenAnswer((_) async => []);
    when(
      () => audit.listVaultLogs(
        'v-1',
        entryId: 'e-1',
        cursor: null,
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => AuditLogPage(
        entries: [
          AuditLogEntry(
            id: 'bad',
            eventType: AuditEventType.entryUpdated,
            rawEventType: 'entry.updated',
            actorType: AuditActorType.user,
            createdAt: DateTime.utc(2026),
            vaultId: 'other-vault',
            entryId: 'e-1',
          ),
        ],
      ),
    );

    await cubit.load();
    expect(cubit.state.status, EntryLogsStatus.error);
    expect(cubit.state.entries, isEmpty);
  });

  test('missing local references use prefix and suffix fallbacks', () async {
    const purgedVault = '11111111-1111-4111-8111-222222222222';
    const purgedEntry = '33333333-3333-4333-8333-444444444444';
    when(() => agents.listAgents()).thenAnswer((_) async => []);
    vaults.current = const VaultListLoaded([]);
    when(
      () => memberIndex.waitForCurrent(purgedVault),
    ).thenAnswer((_) async {});
    when(() => memberIndex.entries(purgedVault)).thenReturn(const []);
    when(
      () => audit.listVaultLogs(
        purgedVault,
        entryId: purgedEntry,
        cursor: null,
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => AuditLogPage(
        entries: [
          AuditLogEntry(
            id: '1',
            eventType: AuditEventType.entryDeleted,
            rawEventType: 'entry.deleted',
            actorType: AuditActorType.user,
            createdAt: DateTime.utc(2026),
            userId: 'aaaaaaaa-aaaa-4aaa-8aaa-bbbbbbbbbbbb',
            vaultId: purgedVault,
            entryId: purgedEntry,
          ),
        ],
      ),
    );
    final purgedCubit = EntryLogsCubit(
      auditRepository: audit,
      agentsRepository: agents,
      vaultListCubit: vaults,
      vaultMembersRepository: vaultMembers,
      memberSync: memberIndex,
      vaultId: purgedVault,
      entryId: purgedEntry,
    );
    addTearDown(purgedCubit.close);

    await purgedCubit.load();

    expect(purgedCubit.state.entries.single.entryLabel, '33333333…444444');
    expect(
      purgedCubit.state.entries.single.resolvedVaultName,
      '11111111…222222',
    );
  });

  test('rejects a repeated opaque cursor without duplicating rows', () async {
    when(() => agents.listAgents()).thenAnswer((_) async => []);
    when(
      () => audit.listVaultLogs(
        'v-1',
        entryId: 'e-1',
        cursor: null,
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => AuditLogPage(entries: [_entry('1')], nextCursor: 'c1'),
    );
    when(
      () => audit.listVaultLogs(
        'v-1',
        entryId: 'e-1',
        cursor: 'c1',
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => AuditLogPage(entries: [_entry('2')], nextCursor: 'c1'),
    );

    await cubit.load();
    await cubit.loadMore();

    expect(cubit.state.entries.map((entry) => entry.id), ['1']);
    expect(cubit.state.loadMoreError, isTrue);
    expect(cubit.state.nextCursor, 'c1');
  });

  test('caps loaded structural rows and stops requesting more pages', () async {
    when(() => agents.listAgents()).thenAnswer((_) async => []);
    List<AuditLogEntry> page(int page) => List.generate(
      50,
      (index) => _entry('${page * 50 + index}'),
      growable: false,
    );
    when(
      () => audit.listVaultLogs(
        'v-1',
        entryId: 'e-1',
        cursor: null,
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => AuditLogPage(entries: page(0), nextCursor: 'c1'));
    for (var current = 1; current < 10; current++) {
      when(
        () => audit.listVaultLogs(
          'v-1',
          entryId: 'e-1',
          cursor: 'c$current',
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async =>
            AuditLogPage(entries: page(current), nextCursor: 'c${current + 1}'),
      );
    }

    await cubit.load();
    for (var page = 1; page < 12; page++) {
      await cubit.loadMore();
    }

    expect(cubit.state.entries, hasLength(500));
    expect(cubit.state.nextCursor, isNull);
    verifyNever(
      () => audit.listVaultLogs(
        'v-1',
        entryId: 'e-1',
        cursor: 'c10',
        pageSize: any(named: 'pageSize'),
      ),
    );
  });

  testWidgets('does not fetch until the Logs tab becomes active', (
    tester,
  ) async {
    when(() => agents.listAgents()).thenAnswer((_) async => []);
    when(
      () => audit.listVaultLogs(
        'v-1',
        entryId: 'e-1',
        cursor: null,
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => const AuditLogPage(entries: []));
    final lazyCubit = EntryLogsCubit(
      auditRepository: audit,
      agentsRepository: agents,
      vaultListCubit: vaults,
      vaultMembersRepository: vaultMembers,
      memberSync: memberIndex,
      vaultId: 'v-1',
      entryId: 'e-1',
    );

    Widget app(bool active) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EntryLogsTab(
          key: const ValueKey('logs'),
          vaultId: 'v-1',
          entryId: 'e-1',
          active: active,
          cubit: lazyCubit,
        ),
      ),
    );

    await tester.pumpWidget(app(false));
    verifyNever(
      () => audit.listVaultLogs(
        'v-1',
        entryId: 'e-1',
        cursor: null,
        pageSize: any(named: 'pageSize'),
      ),
    );

    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    verify(
      () => audit.listVaultLogs(
        'v-1',
        entryId: 'e-1',
        cursor: null,
        pageSize: any(named: 'pageSize'),
      ),
    ).called(1);

    // Switching away and back keeps the already-loaded feed. A refresh is an
    // explicit user action, not a side effect of selecting the tab.
    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    verifyNever(
      () => audit.listVaultLogs(
        'v-1',
        entryId: 'e-1',
        cursor: null,
        pageSize: any(named: 'pageSize'),
      ),
    );
  });
}

VaultEntity _vault() => VaultEntity(
  id: 'v-1',
  name: 'Local Vault',
  grantMode: GrantMode.granular,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  entryCount: 1,
  activeGrantCount: 0,
  memberCount: 1,
);

MemberIndexEntry _memberEntry() => const MemberIndexEntry(
  entryId: 'e-1',
  entryType: 0,
  memberLabel: 'Local Entry',
  searchFields: [],
  revision: '1',
  state: MemberEntryState.active,
);
