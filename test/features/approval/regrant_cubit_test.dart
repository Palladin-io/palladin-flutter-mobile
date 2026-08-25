import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/approval/domain/repositories/approval_repository.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/regrant_cubit.dart';
import 'package:mobile_palladin/features/agents/domain/entities/agent.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant_method.dart';

class _MockApprovalRepository extends Mock implements ApprovalRepository {}

class _MockAgentsRepository extends Mock implements AgentsRepository {}

void main() {
  late ApprovalRepository repository;
  late AgentsRepository agentsRepository;
  late RegrantCubit cubit;

  const args = (
    vaultId: 'vault-1',
    agentId: 'agent-1',
    isFull: false,
    entryId: 'entry-1',
  );

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const GrantLifetime());
    registerFallbackValue(GrantMethod.get);
  });

  setUp(() {
    repository = _MockApprovalRepository();
    agentsRepository = _MockAgentsRepository();
    when(() => agentsRepository.getAgent('agent-1')).thenAnswer(
      (_) async => Agent(
        agentId: 'agent-1',
        name: 'Agent',
        status: AgentStatus.active,
        publicKeySuffix: 'suffix',
        publicKey: 'fresh-public-key',
        recipientKeyVersion: 8,
        accessEpoch: 5,
        createdAt: DateTime.utc(2026),
      ),
    );
    cubit = RegrantCubit(
      repository: repository,
      agentsRepository: agentsRepository,
      args: args,
    );
  });

  tearDown(() => cubit.close());

  test(
    'uses the current Agent binding and preserves owner-selected methods',
    () async {
      when(
        () => repository.createGrant(
          vaultId: any(named: 'vaultId'),
          agentId: any(named: 'agentId'),
          agentPublicKey: any(named: 'agentPublicKey'),
          recipientKeyVersion: any(named: 'recipientKeyVersion'),
          agentAccessEpoch: any(named: 'agentAccessEpoch'),
          isFull: any(named: 'isFull'),
          entryId: any(named: 'entryId'),
          privateKey: any(named: 'privateKey'),
          limit: any(named: 'limit'),
          methods: any(named: 'methods'),
        ),
      ).thenAnswer((_) async {});

      await cubit.submit(
        privateKey: Uint8List.fromList([1, 2, 3]),
        limit: const GrantLifetime(),
        methods: const [GrantMethod.get],
      );

      verify(
        () => repository.createGrant(
          vaultId: 'vault-1',
          agentId: 'agent-1',
          agentPublicKey: 'fresh-public-key',
          recipientKeyVersion: 8,
          agentAccessEpoch: 5,
          isFull: false,
          entryId: 'entry-1',
          privateKey: any(named: 'privateKey'),
          limit: any(named: 'limit'),
          methods: const [GrantMethod.get],
        ),
      ).called(1);
      verify(() => agentsRepository.getAgent('agent-1')).called(1);
    },
  );
}
