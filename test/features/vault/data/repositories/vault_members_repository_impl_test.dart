import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_members_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/vault_member_model.dart';
import 'package:mobile_palladin/features/vault/data/repositories/vault_members_repository_impl.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_member.dart';

class _Remote extends Mock implements VaultMembersRemote {}

VaultMemberModel _member(String id, String status) => VaultMemberModel(
  memberId: id,
  addedAt: '2026-07-01T10:00:00Z',
  deprovisioningStatus: status,
);

void main() {
  test('paginates with a bound and preserves staged statuses', () async {
    final remote = _Remote();
    when(() => remote.list('vault-1')).thenAnswer(
      (_) async => VaultMemberPage(
        items: [_member('member-1', 'Active')],
        nextAfterId: 'member-1',
      ),
    );
    when(() => remote.list('vault-1', afterId: 'member-1')).thenAnswer(
      (_) async =>
          VaultMemberPage(items: [_member('member-2', 'BlockedLastMember')]),
    );

    final result = await VaultMembersRepositoryImpl(remote).list('vault-1');

    expect(result.map((item) => item.status), [
      VaultMemberStatus.active,
      VaultMemberStatus.blockedLastMember,
    ]);
  });

  test('fails closed when a cursor repeats', () async {
    final remote = _Remote();
    when(
      () => remote.list('vault-1', afterId: any(named: 'afterId')),
    ).thenAnswer(
      (_) async => VaultMemberPage(
        items: [_member('member-1', 'Active')],
        nextAfterId: 'same-cursor',
      ),
    );

    await expectLater(
      VaultMembersRepositoryImpl(remote).list('vault-1'),
      throwsFormatException,
    );
  });

  test('fails closed for an unknown server status', () {
    expect(
      () => _member('member-1', 'AlmostRemoved').toEntity(),
      throwsFormatException,
    );
  });
}
