import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/agents/domain/entities/agent.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/domain/exceptions/audit_exceptions.dart';
import 'package:mobile_palladin/features/audit/domain/repositories/audit_repository.dart';
import 'package:mobile_palladin/features/audit/presentation/cubit/entry_logs_cubit.dart';

class _MockAuditRepository extends Mock implements AuditRepository {}

class _MockAgentsRepository extends Mock implements AgentsRepository {}

AuditLogEntry _entry(String id, {String? agentId}) {
  return AuditLogEntry(
    id: id,
    eventType: AuditEventType.credentialAccessed,
    rawEventType: 'credential.accessed',
    actorType: AuditActorType.agent,
    createdAt: DateTime(2026, 6, 1, 10),
    agentId: agentId,
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
  late EntryLogsCubit cubit;

  setUp(() {
    audit = _MockAuditRepository();
    agents = _MockAgentsRepository();
    cubit = EntryLogsCubit(
      auditRepository: audit,
      agentsRepository: agents,
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
}
