import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/settings/domain/entities/organization_management.dart';
import 'package:mobile_palladin/features/settings/domain/repositories/settings_repository.dart';
import 'package:mobile_palladin/features/settings/presentation/bloc/team_cubit.dart';

class _Repository extends Mock implements SettingsRepository {}

void main() {
  late _Repository repository;

  setUp(() {
    repository = _Repository();
    when(
      () => repository.listOrganizationMembers(),
    ).thenAnswer((_) async => [_member]);
  });

  blocTest<TeamCubit, TeamState>(
    'a read-only member loads only the public Team directory',
    build: () => TeamCubit(repository: repository),
    act: (cubit) => cubit.load(canInvite: false, canManage: false),
    expect: () => [
      isA<TeamState>().having(
        (state) => state.status,
        'status',
        TeamStatus.loading,
      ),
      isA<TeamState>()
          .having((state) => state.status, 'status', TeamStatus.loaded)
          .having((state) => state.members.single.email, 'email', 'a@b.test')
          .having((state) => state.invitations, 'invitations', isEmpty)
          .having((state) => state.roles, 'roles', isEmpty),
    ],
    verify: (_) {
      verify(() => repository.listOrganizationMembers()).called(1);
      verifyNever(() => repository.listOrganizationInvitations());
      verifyNever(() => repository.listInvitationRoles());
      verifyNever(() => repository.listOrganizationRoles());
    },
  );

  blocTest<TeamCubit, TeamState>(
    'authorized invitation uses the backend role and refreshes the queue',
    build: () {
      when(
        () => repository.listOrganizationInvitations(),
      ).thenAnswer((_) async => const <OrganizationInvitation>[]);
      when(() => repository.listInvitationRoles()).thenAnswer(
        (_) async => const [InvitationRole(id: 'role-user', name: 'User')],
      );
      when(
        () => repository.inviteOrganizationMember(any(), any()),
      ).thenAnswer((_) async {});
      return TeamCubit(repository: repository);
    },
    act: (cubit) async {
      await cubit.load(canInvite: true, canManage: false);
      await cubit.invite(email: '  new@example.com ', roleId: 'role-user');
    },
    verify: (_) {
      verify(
        () =>
            repository.inviteOrganizationMember('new@example.com', 'role-user'),
      ).called(1);
      verify(() => repository.listOrganizationInvitations()).called(2);
    },
  );
}

const _role = OrganizationRole(
  id: 'role-user',
  name: 'User',
  permissions: 0,
  isSystem: true,
  canAssign: true,
  assignedMemberCount: 1,
);

final _member = OrganizationMember(
  userId: 'user-1',
  displayName: 'A',
  email: 'a@b.test',
  publicKey: null,
  roles: const [_role],
  effectivePermissions: 0,
  isOwner: false,
  joinedAt: DateTime.utc(2026, 8, 1),
  status: 'Active',
);
