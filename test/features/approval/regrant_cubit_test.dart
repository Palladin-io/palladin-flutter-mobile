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

  const args = GranularRegrantArgs(
    vaultId: 'vault-1',
    agentId: 'agent-1',
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
    cubit = GranularRegrantCubit(
      repository: repository,
      agentsRepository: agentsRepository,
      vaultId: args.vaultId,
      agentId: args.agentId,
      entryId: args.entryId,
    );
  });

  tearDown(() => cubit.close());

  test(
    'uses the current Agent binding and preserves owner-selected methods',
    () async {
      when(
        () => repository.createGranularGrant(
          vaultId: any(named: 'vaultId'),
          entryId: any(named: 'entryId'),
          agentId: any(named: 'agentId'),
          agentPublicKey: any(named: 'agentPublicKey'),
          recipientKeyVersion: any(named: 'recipientKeyVersion'),
          agentAccessEpoch: any(named: 'agentAccessEpoch'),
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
        () => repository.createGranularGrant(
          vaultId: 'vault-1',
          entryId: 'entry-1',
          agentId: 'agent-1',
          agentPublicKey: 'fresh-public-key',
          recipientKeyVersion: 8,
          agentAccessEpoch: 5,
          privateKey: any(named: 'privateKey'),
          limit: any(named: 'limit'),
          methods: const [GrantMethod.get],
        ),
      ).called(1);
      verify(() => agentsRepository.getAgent('agent-1')).called(1);
    },
  );

  test('retains restricted fields while renewing access', () async {
    await cubit.close();
    cubit = GranularRegrantCubit(
      repository: repository,
      agentsRepository: agentsRepository,
      vaultId: args.vaultId,
      agentId: args.agentId,
      entryId: args.entryId,
      selectedFieldIds: const ['credential.password'],
    );
    when(
      () => repository.createGranularGrant(
        vaultId: any(named: 'vaultId'),
        entryId: any(named: 'entryId'),
        selectedFieldIds: const ['credential.password'],
        agentId: any(named: 'agentId'),
        agentPublicKey: any(named: 'agentPublicKey'),
        recipientKeyVersion: any(named: 'recipientKeyVersion'),
        agentAccessEpoch: any(named: 'agentAccessEpoch'),
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
      () => repository.createGranularGrant(
        vaultId: 'vault-1',
        entryId: 'entry-1',
        selectedFieldIds: const ['credential.password'],
        agentId: 'agent-1',
        agentPublicKey: 'fresh-public-key',
        recipientKeyVersion: 8,
        agentAccessEpoch: 5,
        privateKey: any(named: 'privateKey'),
        limit: any(named: 'limit'),
        methods: const [GrantMethod.get],
      ),
    ).called(1);
    verify(() => agentsRepository.getAgent('agent-1')).called(1);
  });

  test('FULL flow cannot carry an Entry contract', () async {
    await cubit.close();
    cubit = FullRegrantCubit(
      repository: repository,
      agentsRepository: agentsRepository,
      vaultId: 'vault-1',
      agentId: 'agent-1',
    );
    when(
      () => repository.createFullGrant(
        vaultId: any(named: 'vaultId'),
        agentId: any(named: 'agentId'),
        agentPublicKey: any(named: 'agentPublicKey'),
        recipientKeyVersion: any(named: 'recipientKeyVersion'),
        agentAccessEpoch: any(named: 'agentAccessEpoch'),
        privateKey: any(named: 'privateKey'),
        limit: any(named: 'limit'),
        methods: any(named: 'methods'),
      ),
    ).thenAnswer((_) async {});

    await cubit.submit(
      privateKey: Uint8List.fromList([1, 2, 3]),
      limit: const GrantLifetime(),
      methods: const [GrantMethod.inject],
    );

    verify(
      () => repository.createFullGrant(
        vaultId: 'vault-1',
        agentId: 'agent-1',
        agentPublicKey: 'fresh-public-key',
        recipientKeyVersion: 8,
        agentAccessEpoch: 5,
        privateKey: any(named: 'privateKey'),
        limit: any(named: 'limit'),
        methods: const [GrantMethod.inject],
      ),
    ).called(1);
    verifyNever(
      () => repository.createGranularGrant(
        vaultId: any(named: 'vaultId'),
        entryId: any(named: 'entryId'),
        agentId: any(named: 'agentId'),
        agentPublicKey: any(named: 'agentPublicKey'),
        recipientKeyVersion: any(named: 'recipientKeyVersion'),
        agentAccessEpoch: any(named: 'agentAccessEpoch'),
        privateKey: any(named: 'privateKey'),
        limit: any(named: 'limit'),
        methods: any(named: 'methods'),
      ),
    );
  });

  test(
    'Script execution refreshes Agent binding and stays Exec-only',
    () async {
      await cubit.close();
      cubit = ScriptExecutionRegrantCubit(
        repository: repository,
        agentsRepository: agentsRepository,
        vaultId: 'vault-1',
        agentId: 'agent-1',
        scriptEntryId: 'script-1',
      );
      when(
        () => repository.createScriptExecutionGrant(
          vaultId: any(named: 'vaultId'),
          scriptEntryId: any(named: 'scriptEntryId'),
          agentId: any(named: 'agentId'),
          agentPublicKey: any(named: 'agentPublicKey'),
          recipientKeyVersion: any(named: 'recipientKeyVersion'),
          agentAccessEpoch: any(named: 'agentAccessEpoch'),
          privateKey: any(named: 'privateKey'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async {});

      await cubit.submit(
        privateKey: Uint8List.fromList([1, 2, 3]),
        limit: const GrantLifetime(),
        methods: const [GrantMethod.exec],
      );

      verify(
        () => repository.createScriptExecutionGrant(
          vaultId: 'vault-1',
          scriptEntryId: 'script-1',
          agentId: 'agent-1',
          agentPublicKey: 'fresh-public-key',
          recipientKeyVersion: 8,
          agentAccessEpoch: 5,
          privateKey: any(named: 'privateKey'),
          limit: any(named: 'limit'),
        ),
      ).called(1);
      verify(() => agentsRepository.getAgent('agent-1')).called(1);
    },
  );
}
