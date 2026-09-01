import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/widgets/sheet_action_buttons.dart';
import 'package:mobile_palladin/core/widgets/sheet_drag_handle.dart';
import 'package:mobile_palladin/features/settings/domain/entities/org.dart';
import 'package:mobile_palladin/features/settings/domain/entities/organization_management.dart';
import 'package:mobile_palladin/features/settings/domain/exceptions/settings_exceptions.dart';
import 'package:mobile_palladin/features/settings/domain/repositories/settings_repository.dart';
import 'package:mobile_palladin/features/settings/presentation/bloc/permissions_cubit.dart';
import 'package:mobile_palladin/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:mobile_palladin/features/settings/presentation/bloc/team_cubit.dart';
import 'package:mobile_palladin/features/settings/presentation/pages/permissions_page.dart';
import 'package:mobile_palladin/features/settings/presentation/pages/team_page.dart';
import 'package:mobile_palladin/features/settings/presentation/widgets/system_role_badge.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Repository extends Mock implements SettingsRepository {}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}

void main() {
  testWidgets('invite sheet owns root modal chrome and canonical footer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _Repository();
    when(
      () => repository.listOrganizationMembers(),
    ).thenAnswer((_) async => const []);
    when(
      () => repository.listOrganizationInvitations(),
    ).thenAnswer((_) async => const []);
    when(() => repository.listInvitationRoles()).thenAnswer(
      (_) async => const [InvitationRole(id: 'role-user', name: 'User')],
    );
    when(() => repository.getOrg()).thenAnswer(
      (_) async => const Org(
        orgId: 'org-1',
        name: 'Example',
        planType: 'Free',
        memberCount: 1,
        seatUsage: 1,
        seatLimit: 2,
      ),
    );
    final cubit = TeamCubit(repository: repository);
    await cubit.load(canInvite: true, canManage: false);
    addTearDown(cubit.close);
    final settingsCubit = SettingsCubit(repository: repository);
    await settingsCubit.loadOrg();
    addTearDown(settingsCubit.close);

    final rootObserver = _RecordingNavigatorObserver();
    final nestedObserver = _RecordingNavigatorObserver();
    final bottomNavChanges = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [rootObserver],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<TeamCubit>.value(
          value: cubit,
          child: AppShellScope(
            openSettingsDrawer: () {},
            setBottomNavHidden: bottomNavChanges.add,
            setFab: (_, _) {},
            clearFab: (_) {},
            child: Navigator(
              observers: [nestedObserver],
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => InviteMemberSheet.show(
                        context,
                        settingsCubit: settingsCubit,
                      ),
                      child: const Text('Open invite'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    rootObserver.routes.clear();
    nestedObserver.routes.clear();

    await tester.tap(find.text('Open invite'));
    await tester.pumpAndSettle();

    expect(bottomNavChanges, [true]);
    expect(rootObserver.routes.whereType<PopupRoute<dynamic>>(), hasLength(1));
    expect(nestedObserver.routes.whereType<PopupRoute<dynamic>>(), isEmpty);
    expect(find.byType(SheetDragHandle), findsNothing);
    expect(find.byType(SheetActionButtons), findsOneWidget);
    expect(find.text('1 of 2 seats used'), findsOneWidget);
    expect(find.text('1 available'), findsOneWidget);
    expect(find.text('Manage seats'), findsNothing);
    expect(
      tester.getSize(find.byType(SheetActionButtons)).width,
      tester.getSize(find.byType(InviteMemberSheet)).width,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(bottomNavChanges, [true, false]);
  });

  testWidgets('full organization opens seat guidance instead of invite form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _Repository();
    when(
      () => repository.listOrganizationMembers(),
    ).thenAnswer((_) async => const []);
    when(
      () => repository.listOrganizationInvitations(),
    ).thenAnswer((_) async => const []);
    when(() => repository.listInvitationRoles()).thenAnswer(
      (_) async => const [InvitationRole(id: 'role-user', name: 'User')],
    );
    when(() => repository.getOrg()).thenAnswer(
      (_) async => const Org(
        orgId: 'org-1',
        name: 'Example',
        planType: 'Free',
        memberCount: 1,
        seatUsage: 1,
        seatLimit: 1,
      ),
    );
    final cubit = TeamCubit(repository: repository);
    await cubit.load(canInvite: true, canManage: false);
    addTearDown(cubit.close);
    final settingsCubit = SettingsCubit(repository: repository);
    await settingsCubit.loadOrg();
    addTearDown(settingsCubit.close);

    final bottomNavChanges = <bool>[];
    InviteMemberSheetResult? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<TeamCubit>.value(
          value: cubit,
          child: AppShellScope(
            openSettingsDrawer: () {},
            setBottomNavHidden: bottomNavChanges.add,
            setFab: (_, _) {},
            clearFab: (_) {},
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      result = await InviteMemberSheet.show(
                        context,
                        settingsCubit: settingsCubit,
                      );
                    },
                    child: const Text('Open invite'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open invite'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('invite-no-seats-state')), findsOneWidget);
    expect(find.text('No seats available'), findsOneWidget);
    expect(find.text('Invite a member'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(SheetActionButtons), findsNothing);
    expect(
      find.byKey(const ValueKey('manage-seats-primary-action')),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Manage seats'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('no-seats-usage-summary')),
      findsOneWidget,
    );
    expect(find.text('Seat usage'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    final usageProgress = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(const ValueKey('no-seats-usage-summary')),
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(usageProgress.value, 1);

    await tester.tap(find.text('Manage seats'));
    await tester.pumpAndSettle();

    expect(result, InviteMemberSheetResult.manageSeats);
    expect(bottomNavChanges, [true, false]);
  });

  testWidgets('invite keeps the draft and shows a seat-limit error inline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _Repository();
    when(
      () => repository.listOrganizationMembers(),
    ).thenAnswer((_) async => const []);
    when(
      () => repository.listOrganizationInvitations(),
    ).thenAnswer((_) async => const []);
    when(() => repository.listInvitationRoles()).thenAnswer(
      (_) async => const [InvitationRole(id: 'role-user', name: 'User')],
    );
    when(() => repository.getOrg()).thenAnswer(
      (_) async => const Org(
        orgId: 'org-1',
        name: 'Example',
        planType: 'Free',
        memberCount: 1,
        seatUsage: 1,
        seatLimit: 2,
      ),
    );
    when(
      () => repository.inviteOrganizationMember(any(), any()),
    ).thenThrow(const SettingsException(SettingsErrorKind.seatLimitReached));
    final cubit = TeamCubit(repository: repository);
    await cubit.load(canInvite: true, canManage: false);
    addTearDown(cubit.close);
    final settingsCubit = SettingsCubit(repository: repository);
    await settingsCubit.loadOrg();
    addTearDown(settingsCubit.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<TeamCubit>.value(
          value: cubit,
          child: AppShellScope(
            openSettingsDrawer: () {},
            setBottomNavHidden: (_) {},
            setFab: (_, _) {},
            clearFab: (_) {},
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => InviteMemberSheet.show(
                      context,
                      settingsCubit: settingsCubit,
                    ),
                    child: const Text('Open invite'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open invite'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new@example.com');
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();

    expect(find.byType(InviteMemberSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-action-error')), findsOneWidget);
    expect(
      find.text('The organization has no available seats.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Manage seats'), findsOneWidget);
    expect(find.text('new@example.com'), findsOneWidget);
    verify(
      () => repository.inviteOrganizationMember('new@example.com', 'role-user'),
    ).called(1);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('system role marker is rendered as a chip', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: SystemRoleBadge())),
      ),
    );

    expect(find.text('System'), findsOneWidget);
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(SystemRoleBadge),
        matching: find.byType(Container),
      ),
    );
    expect(container.decoration, isA<BoxDecoration>());
    expect((container.decoration! as BoxDecoration).borderRadius, isNotNull);
  });

  testWidgets('team member footer shows roles left and joined date right', (
    tester,
  ) async {
    final member = OrganizationMember(
      userId: 'user-1',
      displayName: 'Ada Lovelace',
      email: 'ada@example.com',
      publicKey: null,
      roles: const [
        OrganizationRole(
          id: 'role-user',
          name: 'User',
          permissions: 0,
          isSystem: true,
          canAssign: true,
          assignedMemberCount: 1,
        ),
        OrganizationRole(
          id: 'role-auditor',
          name: 'Auditor',
          permissions: 0,
          isSystem: false,
          canAssign: true,
          assignedMemberCount: 1,
        ),
      ],
      effectivePermissions: 0,
      isOwner: false,
      joinedAt: DateTime.utc(2026, 9, 1, 12),
      status: 'active',
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              child: TeamMemberCard(member: member, onTap: () {}),
            ),
          ),
        ),
      ),
    );

    final roles = find.text('2 roles');
    final joined = find.text('Joined Sep 1, 2026');
    expect(
      find.byKey(const ValueKey('team-member-card-footer')),
      findsOneWidget,
    );
    expect(roles, findsOneWidget);
    expect(joined, findsOneWidget);
    expect(tester.getCenter(roles).dx, lessThan(tester.getCenter(joined).dx));
    final footer = tester.getRect(
      find.byKey(const ValueKey('team-member-card-footer')),
    );
    expect(footer.right - tester.getRect(joined).right, lessThanOrEqualTo(16));
  });

  testWidgets('system role marker stays beside the right-aligned role name', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: ValueKey('role-row-host'),
              width: 280,
              child: RoleNameRow(isSystem: true, name: Text('Administrator')),
            ),
          ),
        ),
      ),
    );

    final row = find.byType(RoleNameRow);
    final badge = find.byType(SystemRoleBadge);
    expect(
      tester.getCenter(find.text('Administrator')).dy,
      tester.getCenter(badge).dy,
    );
    expect(tester.getTopRight(badge).dx, tester.getTopRight(row).dx);
  });

  testWidgets('create role sheet uses root modal and hides Shell navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _Repository();
    when(() => repository.listOrganizationRoles()).thenAnswer(
      (_) async =>
          const OrganizationRoles(items: [], assignablePermissions: []),
    );
    final cubit = PermissionsCubit(repository: repository);
    await cubit.load();
    addTearDown(cubit.close);

    final rootObserver = _RecordingNavigatorObserver();
    final nestedObserver = _RecordingNavigatorObserver();
    final bottomNavChanges = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [rootObserver],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<PermissionsCubit>.value(
          value: cubit,
          child: AppShellScope(
            openSettingsDrawer: () {},
            setBottomNavHidden: bottomNavChanges.add,
            setFab: (_, _) {},
            clearFab: (_) {},
            child: Navigator(
              observers: [nestedObserver],
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => CreateRoleSheet.show(context),
                      child: const Text('Open create role'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    rootObserver.routes.clear();
    nestedObserver.routes.clear();

    await tester.tap(find.text('Open create role'));
    await tester.pumpAndSettle();

    expect(bottomNavChanges, [true]);
    expect(rootObserver.routes.whereType<PopupRoute<dynamic>>(), hasLength(1));
    expect(nestedObserver.routes.whereType<PopupRoute<dynamic>>(), isEmpty);
    expect(find.byType(SheetDragHandle), findsOneWidget);
    expect(find.byType(SheetActionButtons), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(bottomNavChanges, [true, false]);
  });
}
