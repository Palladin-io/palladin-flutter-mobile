import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/agents/domain/entities/agent.dart';
import 'package:mobile_palladin/features/agents/domain/exceptions/agents_exceptions.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/agents/presentation/bloc/agents_cubit.dart';

class _MockAgentsRepository extends Mock implements AgentsRepository {}

void main() {
  late _MockAgentsRepository repository;

  Agent agent(String id, AgentStatus status) => Agent(
    agentId: id,
    name: 'agent-$id',
    status: status,
    publicKeySuffix: 'a8f2c4d1',
    createdAt: DateTime.utc(2026, 2, 20),
    enrolledAt: status == AgentStatus.pending
        ? null
        : DateTime.utc(2026, 2, 20),
  );

  final pendingList = <Agent>[agent('a1', AgentStatus.pending)];
  final activeList = <Agent>[agent('a1', AgentStatus.active)];
  final deactivatedList = <Agent>[agent('a1', AgentStatus.deactivated)];
  final mixedList = <Agent>[
    agent('a1', AgentStatus.active),
    agent('a2', AgentStatus.pending),
    agent('a3', AgentStatus.deactivated),
  ];

  setUp(() {
    repository = _MockAgentsRepository();
  });

  AgentsCubit buildCubit() => AgentsCubit(repository: repository);

  group('AgentsCubit.load', () {
    blocTest<AgentsCubit, AgentsState>(
      'emits loading then loaded with agents',
      build: () {
        when(() => repository.listAgents()).thenAnswer((_) async => mixedList);
        return buildCubit();
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<AgentsState>().having(
          (s) => s.status,
          'status',
          AgentsStatus.loading,
        ),
        isA<AgentsState>()
            .having((s) => s.status, 'status', AgentsStatus.loaded)
            .having((s) => s.agents.length, 'agents.length', 3)
            .having((s) => s.activeCount, 'activeCount', 1),
      ],
    );

    blocTest<AgentsCubit, AgentsState>(
      'emits error on network failure',
      build: () {
        when(
          () => repository.listAgents(),
        ).thenThrow(const AgentsException(AgentsErrorKind.networkError));
        return buildCubit();
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<AgentsState>().having(
          (s) => s.status,
          'status',
          AgentsStatus.loading,
        ),
        isA<AgentsState>()
            .having((s) => s.status, 'status', AgentsStatus.error)
            .having((s) => s.error, 'error', AgentsErrorKind.networkError),
      ],
    );

    test('concurrent refresh calls share one repository request', () async {
      final pending = Completer<List<Agent>>();
      when(() => repository.listAgents()).thenAnswer((_) => pending.future);
      final cubit = buildCubit();

      final first = cubit.refresh();
      final second = cubit.refresh();

      expect(identical(first, second), isTrue);
      pending.complete(mixedList);
      await Future.wait([first, second]);

      verify(() => repository.listAgents()).called(1);
      expect(cubit.state.status, AgentsStatus.loaded);
      await cubit.close();
    });

    test(
      'event refresh queues exactly one request after an active load',
      () async {
        final first = Completer<List<Agent>>();
        final trailing = Completer<List<Agent>>();
        var calls = 0;
        when(() => repository.listAgents()).thenAnswer((_) {
          calls += 1;
          return calls == 1 ? first.future : trailing.future;
        });
        final cubit = buildCubit();

        final load = cubit.load();
        final fresh = cubit.refresh(ensureFresh: true);
        final sameFresh = cubit.refresh(ensureFresh: true);

        expect(identical(fresh, sameFresh), isTrue);
        first.complete(pendingList);
        await load;
        expect(calls, 2);

        trailing.complete(activeList);
        await Future.wait([fresh, sameFresh]);

        verify(() => repository.listAgents()).called(2);
        expect(cubit.state.agents.single.status, AgentStatus.active);
        await cubit.close();
      },
    );
  });

  group('AgentsState.agentById', () {
    test('resolves an agent present in the list', () {
      final state = AgentsState(status: AgentsStatus.loaded, agents: mixedList);
      expect(state.agentById('a2')?.status, AgentStatus.pending);
    });

    test('returns null for an unknown id', () {
      final state = AgentsState(status: AgentsStatus.loaded, agents: mixedList);
      expect(state.agentById('missing'), isNull);
    });
  });

  group('AgentsCubit.approveAgent', () {
    blocTest<AgentsCubit, AgentsState>(
      'approves then refreshes the list',
      build: () {
        when(() => repository.approveAgent(any())).thenAnswer((_) async {});
        when(() => repository.listAgents()).thenAnswer((_) async => activeList);
        return buildCubit();
      },
      act: (cubit) => cubit.approveAgent('a1'),
      expect: () => [
        isA<AgentsState>().having(
          (s) => s.mutatingAgentId,
          'mutatingAgentId',
          'a1',
        ),
        isA<AgentsState>()
            .having((s) => s.status, 'status', AgentsStatus.loaded)
            .having((s) => s.mutatingAgentId, 'mutatingAgentId', isNull)
            .having(
              (s) => s.agents.single.status,
              'agent.status',
              AgentStatus.active,
            ),
      ],
      verify: (_) {
        verify(() => repository.approveAgent('a1')).called(1);
        verify(() => repository.listAgents()).called(1);
      },
    );

    blocTest<AgentsCubit, AgentsState>(
      'forwards trimmed name, type and iconKey to the repository',
      build: () {
        when(
          () => repository.approveAgent(
            any(),
            name: any(named: 'name'),
            type: any(named: 'type'),
            iconKey: any(named: 'iconKey'),
          ),
        ).thenAnswer((_) async {});
        when(() => repository.listAgents()).thenAnswer((_) async => activeList);
        return buildCubit();
      },
      act: (cubit) => cubit.approveAgent(
        'a1',
        name: '  Build bot  ',
        type: 'claudeCode',
        iconKey: 'terminal',
      ),
      verify: (_) {
        verify(
          () => repository.approveAgent(
            'a1',
            name: 'Build bot',
            type: 'claudeCode',
            iconKey: 'terminal',
          ),
        ).called(1);
      },
    );

    blocTest<AgentsCubit, AgentsState>(
      'sends a blank name as null so the server keeps its default',
      build: () {
        when(
          () => repository.approveAgent(
            any(),
            name: any(named: 'name'),
            type: any(named: 'type'),
            iconKey: any(named: 'iconKey'),
          ),
        ).thenAnswer((_) async {});
        when(() => repository.listAgents()).thenAnswer((_) async => activeList);
        return buildCubit();
      },
      act: (cubit) => cubit.approveAgent('a1', name: '   '),
      verify: (_) {
        verify(
          () => repository.approveAgent(
            'a1',
            name: null,
            type: null,
            iconKey: null,
          ),
        ).called(1);
      },
    );

    blocTest<AgentsCubit, AgentsState>(
      'surfaces a transient mutationError without flipping status on failure',
      build: () {
        when(
          () => repository.approveAgent(any()),
        ).thenThrow(const AgentsException(AgentsErrorKind.forbidden));
        return buildCubit();
      },
      act: (cubit) => cubit.approveAgent('a1'),
      expect: () => [
        isA<AgentsState>().having(
          (s) => s.mutatingAgentId,
          'mutatingAgentId',
          'a1',
        ),
        // A failed mutation must keep status untouched (so the card
        // stays visible) and only set the transient mutationError.
        isA<AgentsState>()
            .having((s) => s.status, 'status', AgentsStatus.initial)
            .having((s) => s.error, 'error', isNull)
            .having(
              (s) => s.mutationError,
              'mutationError',
              AgentsErrorKind.forbidden,
            )
            .having((s) => s.mutatingAgentId, 'mutatingAgentId', isNull),
      ],
      verify: (_) {
        verifyNever(() => repository.listAgents());
      },
    );
  });

  group('AgentsCubit.deactivateAgent', () {
    blocTest<AgentsCubit, AgentsState>(
      'deactivates then refreshes the list',
      build: () {
        when(() => repository.deactivateAgent(any())).thenAnswer((_) async {});
        when(
          () => repository.listAgents(),
        ).thenAnswer((_) async => deactivatedList);
        return buildCubit();
      },
      act: (cubit) => cubit.deactivateAgent('a1'),
      expect: () => [
        isA<AgentsState>().having(
          (s) => s.mutatingAgentId,
          'mutatingAgentId',
          'a1',
        ),
        isA<AgentsState>()
            .having((s) => s.status, 'status', AgentsStatus.loaded)
            .having((s) => s.mutatingAgentId, 'mutatingAgentId', isNull)
            .having(
              (s) => s.agents.single.status,
              'agent.status',
              AgentStatus.deactivated,
            ),
      ],
      verify: (_) {
        verify(() => repository.deactivateAgent('a1')).called(1);
        verify(() => repository.listAgents()).called(1);
      },
    );
  });

  group('AgentsCubit.reactivateAgent', () {
    blocTest<AgentsCubit, AgentsState>(
      'reactivates then refreshes the list',
      build: () {
        when(() => repository.reactivateAgent(any())).thenAnswer((_) async {});
        when(() => repository.listAgents()).thenAnswer((_) async => activeList);
        return buildCubit();
      },
      act: (cubit) => cubit.reactivateAgent('a1'),
      expect: () => [
        isA<AgentsState>().having(
          (s) => s.mutatingAgentId,
          'mutatingAgentId',
          'a1',
        ),
        isA<AgentsState>()
            .having((s) => s.status, 'status', AgentsStatus.loaded)
            .having(
              (s) => s.agents.single.status,
              'agent.status',
              AgentStatus.active,
            ),
      ],
      verify: (_) {
        verify(() => repository.reactivateAgent('a1')).called(1);
      },
    );

    blocTest<AgentsCubit, AgentsState>(
      'surfaces a transient mutationError on failure',
      build: () {
        when(
          () => repository.reactivateAgent(any()),
        ).thenThrow(const AgentsException(AgentsErrorKind.networkError));
        return buildCubit();
      },
      act: (cubit) => cubit.reactivateAgent('a1'),
      expect: () => [
        isA<AgentsState>().having(
          (s) => s.mutatingAgentId,
          'mutatingAgentId',
          'a1',
        ),
        isA<AgentsState>()
            .having(
              (s) => s.mutationError,
              'mutationError',
              AgentsErrorKind.networkError,
            )
            .having((s) => s.mutatingAgentId, 'mutatingAgentId', isNull),
      ],
      verify: (_) {
        verifyNever(() => repository.listAgents());
      },
    );
  });

  group('AgentsCubit.updateAgent', () {
    blocTest<AgentsCubit, AgentsState>(
      'trims fields, updates, then patches the agent from getAgent',
      // updateAgent refetches the touched agent via getAgent (not the full
      // list) because the list endpoint may omit detail-only fields such
      // as iconKey — fetching just the one we touched avoids reverting
      // its avatar after save.
      build: () {
        // Pre-load the cubit so we have an agent list to patch into.
        when(() => repository.listAgents()).thenAnswer((_) async => activeList);
        when(
          () => repository.updateAgent(
            any(),
            name: any(named: 'name'),
            description: any(named: 'description'),
            iconKey: any(named: 'iconKey'),
            iconColor: any(named: 'iconColor'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getAgent('a1'),
        ).thenAnswer((_) async => activeList.single);
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.load();
        await cubit.updateAgent(
          'a1',
          name: '  New name  ',
          description: '  desc  ',
        );
      },
      // Skip the two states from the initial load() so we only assert on
      // the updateAgent transitions.
      skip: 2,
      expect: () => [
        isA<AgentsState>().having(
          (s) => s.mutatingAgentId,
          'mutatingAgentId',
          'a1',
        ),
        isA<AgentsState>()
            .having((s) => s.status, 'status', AgentsStatus.loaded)
            .having((s) => s.mutatingAgentId, 'mutatingAgentId', isNull),
      ],
      verify: (_) {
        // Both fields must be trimmed before hitting the API.
        verify(
          () => repository.updateAgent(
            'a1',
            name: 'New name',
            description: 'desc',
            iconKey: null,
            iconColor: null,
          ),
        ).called(1);
        // getAgent — not listAgents — is used to refresh the touched
        // agent after a successful PATCH.
        verify(() => repository.getAgent('a1')).called(1);
      },
    );

    blocTest<AgentsCubit, AgentsState>(
      'surfaces a transient mutationError on failure',
      build: () {
        when(
          () => repository.updateAgent(
            any(),
            name: any(named: 'name'),
            description: any(named: 'description'),
            iconKey: any(named: 'iconKey'),
            iconColor: any(named: 'iconColor'),
          ),
        ).thenThrow(const AgentsException(AgentsErrorKind.validation));
        return buildCubit();
      },
      act: (cubit) => cubit.updateAgent('a1', name: 'x'),
      expect: () => [
        isA<AgentsState>().having(
          (s) => s.mutatingAgentId,
          'mutatingAgentId',
          'a1',
        ),
        isA<AgentsState>()
            .having(
              (s) => s.mutationError,
              'mutationError',
              AgentsErrorKind.validation,
            )
            .having((s) => s.mutatingAgentId, 'mutatingAgentId', isNull),
      ],
      verify: (_) {
        // The PATCH failed before getAgent ran, so no refresh happens.
        verifyNever(() => repository.getAgent(any()));
        verifyNever(() => repository.listAgents());
      },
    );

    blocTest<AgentsCubit, AgentsState>(
      'acknowledgeMutationError clears the transient error',
      build: () {
        when(
          () => repository.updateAgent(
            any(),
            name: any(named: 'name'),
            description: any(named: 'description'),
            iconKey: any(named: 'iconKey'),
            iconColor: any(named: 'iconColor'),
          ),
        ).thenThrow(const AgentsException(AgentsErrorKind.validation));
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.updateAgent('a1', name: 'x');
        cubit.acknowledgeMutationError();
      },
      skip: 2,
      expect: () => [
        isA<AgentsState>().having(
          (s) => s.mutationError,
          'mutationError',
          isNull,
        ),
      ],
    );

    blocTest<AgentsCubit, AgentsState>(
      // The S3 public URL is byte-for-byte identical across re-uploads
      // (same object key), so the form passes `iconKeyDisplay` with a
      // cache-busting `?v=` query while `iconKey` stays canonical. The
      // emitted agent must carry the `?v=` version so the avatar
      // refetches instead of serving the stale cached image.
      'prefers iconKeyDisplay over fresh.iconKey when both differ',
      build: () {
        const canonicalUrl = 'https://s3.test/agent-icons/a1/icon.png';
        when(() => repository.listAgents()).thenAnswer((_) async => activeList);
        when(
          () => repository.updateAgent(
            any(),
            name: any(named: 'name'),
            description: any(named: 'description'),
            iconKey: any(named: 'iconKey'),
            iconColor: any(named: 'iconColor'),
          ),
        ).thenAnswer((_) async {});
        // Backend always returns the canonical URL — never the `?v=`
        // variant — because the cubit strips the query before sending.
        when(() => repository.getAgent('a1')).thenAnswer(
          (_) async => Agent(
            agentId: 'a1',
            name: 'agent-a1',
            status: AgentStatus.active,
            publicKeySuffix: 'a8f2c4d1',
            createdAt: DateTime.utc(2026, 2, 20),
            iconKey: canonicalUrl,
            iconColor: '#48ECDF',
          ),
        );
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.load();
        await cubit.updateAgent(
          'a1',
          iconKey: 'https://s3.test/agent-icons/a1/icon.png',
          iconKeyDisplay: 'https://s3.test/agent-icons/a1/icon.png?v=999',
          iconColor: '#48ECDF',
        );
      },
      skip: 3,
      expect: () => [
        isA<AgentsState>()
            .having(
              (s) => s.agents.single.iconKey,
              'agent.iconKey',
              'https://s3.test/agent-icons/a1/icon.png?v=999',
            )
            .having(
              (s) => s.agents.single.iconColor,
              'agent.iconColor',
              '#48ECDF',
            ),
      ],
    );
  });

  group('AgentStatusExtension.fromWire', () {
    test('maps known wire values', () {
      expect(AgentStatusExtension.fromWire(1), AgentStatus.pending);
      expect(AgentStatusExtension.fromWire(2), AgentStatus.active);
      expect(AgentStatusExtension.fromWire(3), AgentStatus.deactivated);
      expect(AgentStatusExtension.fromWire(4), AgentStatus.deactivating);
    });

    test('falls back to deactivated for unknown values', () {
      expect(AgentStatusExtension.fromWire(99), AgentStatus.deactivated);
      expect(AgentStatusExtension.fromWire(0), AgentStatus.deactivated);
    });
  });

  test('pendingList fixture is wired for sanity', () {
    expect(pendingList.single.isPending, isTrue);
  });

  group('Agent.publicKeyDisplay', () {
    Agent withKey({String prefix = '', String suffix = ''}) => Agent(
      agentId: 'a1',
      name: 'agent',
      status: AgentStatus.active,
      publicKeyPrefix: prefix,
      publicKeySuffix: suffix,
      createdAt: DateTime.utc(2026, 2, 20),
    );

    test('joins prefix and suffix with a bullet separator', () {
      expect(
        withKey(prefix: 'ed25519k', suffix: 'a8f2c4d1').publicKeyDisplay,
        'ed25519k•••a8f2c4d1',
      );
    });

    test('falls back to suffix only when prefix is absent', () {
      expect(withKey(suffix: 'a8f2c4d1').publicKeyDisplay, 'a8f2c4d1');
    });

    test('falls back to a dash when neither part is present', () {
      expect(withKey().publicKeyDisplay, '—');
    });
  });
}
