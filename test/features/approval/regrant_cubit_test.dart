import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/approval/domain/repositories/approval_repository.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/regrant_cubit.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant_method.dart';

class _MockApprovalRepository extends Mock implements ApprovalRepository {}

void main() {
  late ApprovalRepository repository;
  late RegrantCubit cubit;

  const args = (
    vaultId: 'vault-1',
    agentId: 'agent-1',
    agentPublicKey: 'public-key',
    recipientKeyVersion: 3,
    agentAccessEpoch: 1,
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
    cubit = RegrantCubit(repository: repository, args: args);
  });

  tearDown(() => cubit.close());

  test(
    'passes the owner-selected methods without replacing them with defaults',
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
          agentPublicKey: 'public-key',
          recipientKeyVersion: 3,
          agentAccessEpoch: 1,
          isFull: false,
          entryId: 'entry-1',
          privateKey: any(named: 'privateKey'),
          limit: any(named: 'limit'),
          methods: const [GrantMethod.get],
        ),
      ).called(1);
    },
  );
}
