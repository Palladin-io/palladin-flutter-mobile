import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_member.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_members_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_members_cubit.dart';

class _Repository extends Mock implements VaultMembersRepository {}

VaultMember _member(VaultMemberStatus status) =>
    VaultMember(id: 'member-1', addedAt: DateTime(2026), status: status);

void main() {
  test(
    'removal keeps Member visible until backend rotation progresses',
    () async {
      final repository = _Repository();
      when(
        () => repository.list('vault-1'),
      ).thenAnswer((_) async => [_member(VaultMemberStatus.active)]);
      when(
        () => repository.requestRemoval('member-1'),
      ).thenAnswer((_) async {});
      final cubit = VaultMembersCubit(
        repository: repository,
        vaultId: 'vault-1',
      );
      await cubit.load();
      when(() => repository.list('vault-1')).thenAnswer(
        (_) async => [_member(VaultMemberStatus.waitingForRotation)],
      );

      await cubit.requestRemoval(cubit.state.members.single);

      expect(cubit.state.members, hasLength(1));
      expect(
        cubit.state.members.single.status,
        VaultMemberStatus.waitingForRotation,
      );
      expect(cubit.state.removalRequested, isTrue);
      await cubit.close();
    },
  );

  test('last-capable-Member blocker cannot trigger another request', () async {
    final repository = _Repository();
    final cubit = VaultMembersCubit(repository: repository, vaultId: 'vault-1');

    await cubit.requestRemoval(_member(VaultMemberStatus.blockedLastMember));

    verifyNever(() => repository.requestRemoval(any()));
    await cubit.close();
  });
}
