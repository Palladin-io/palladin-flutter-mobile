import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/settings/domain/entities/organization_management.dart';
import 'package:mobile_palladin/features/settings/domain/repositories/settings_repository.dart';
import 'package:mobile_palladin/features/settings/presentation/bloc/permissions_cubit.dart';

class _Repository extends Mock implements SettingsRepository {}

void main() {
  late _Repository repository;

  setUp(() {
    repository = _Repository();
    when(() => repository.listOrganizationRoles()).thenAnswer(
      (_) async => const OrganizationRoles(
        items: [_role],
        assignablePermissions: [
          AssignablePermission(
            key: 'OrganizationManagement',
            value: 2,
            canAssign: true,
          ),
        ],
      ),
    );
  });

  blocTest<PermissionsCubit, PermissionsState>(
    'loads caller-aware role and permission catalogues',
    build: () => PermissionsCubit(repository: repository),
    act: (cubit) => cubit.load(),
    expect: () => [
      isA<PermissionsState>().having(
        (state) => state.status,
        'status',
        PermissionsStatus.loading,
      ),
      isA<PermissionsState>()
          .having((state) => state.status, 'status', PermissionsStatus.loaded)
          .having((state) => state.roles.single.name, 'role', 'Support')
          .having(
            (state) => state.assignablePermissions.single.value,
            'permission',
            2,
          ),
    ],
  );

  blocTest<PermissionsCubit, PermissionsState>(
    'passes the complete permission mask through an update',
    build: () {
      when(
        () => repository.updateOrganizationRole(any(), any(), any()),
      ).thenAnswer((_) async => _role);
      return PermissionsCubit(repository: repository);
    },
    seed: () => const PermissionsState(
      status: PermissionsStatus.loaded,
      roles: [_role],
      assignablePermissions: [],
    ),
    act: (cubit) => cubit.updateRole('role-1', '  Updated ', 0x4002),
    verify: (_) {
      verify(
        () => repository.updateOrganizationRole('role-1', 'Updated', 0x4002),
      ).called(1);
    },
  );
}

const _role = OrganizationRole(
  id: 'role-1',
  name: 'Support',
  permissions: 2,
  isSystem: false,
  canAssign: true,
  assignedMemberCount: 0,
);
