import 'package:mobile_palladin/core/widgets/app_header_surface.dart';
import 'package:go_router/go_router.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/l10n/locale_cubit.dart';
import 'package:mobile_palladin/core/permissions.dart';
import 'package:mobile_palladin/core/router/app_router.dart';
import 'package:mobile_palladin/core/storage/user_preferences.dart';
import 'package:mobile_palladin/core/theme/theme_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/shell/presentation/widgets/settings_drawer.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Preferences extends Mock implements UserPreferences {}

void main() {
  testWidgets('drawer groups and gates organization destinations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpDrawer(int permissions) async {
      final auth = _AuthBloc();
      when(() => auth.state).thenReturn(
        AuthAuthenticated(
          userId: 'user-1',
          isOnboarded: true,
          isVaultLocked: false,
          permissions: permissions,
          email: 'member@example.com',
        ),
      );
      final preferences = _Preferences();
      final theme = ThemeCubit(preferences);
      final locale = LocaleCubit(preferences);
      addTearDown(theme.close);
      addTearDown(locale.close);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: auth),
            BlocProvider<ThemeCubit>.value(value: theme),
            BlocProvider<LocaleCubit>.value(value: locale),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsDrawer(),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpDrawer(Permissions.vaultCreate | Permissions.vaultManage);
    expect(tester.getBottomRight(find.byType(AppHeaderSurface).last).dy, 1400);
    expect(find.text('Organization'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('Billing'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Data import'), findsOneWidget);
    expect(find.text('Permissions'), findsNothing);
    expect(find.text('API keys'), findsNothing);
    expect(find.text('Audit logs'), findsNothing);

    await pumpDrawer(
      Permissions.organizationManagement |
          Permissions.readApiKey |
          Permissions.auditView,
    );
    expect(find.text('Permissions'), findsOneWidget);
    expect(find.text('API keys'), findsOneWidget);
    expect(find.text('Audit logs'), findsOneWidget);

    await pumpDrawer(Permissions.administratorRoleMask);
    expect(find.text('Permissions'), findsOneWidget);
    expect(find.text('API keys'), findsOneWidget);
    expect(find.text('Audit logs'), findsOneWidget);
  });

  testWidgets('Back from a drawer destination restores the menu', (
    tester,
  ) async {
    final auth = _AuthBloc();
    when(() => auth.state).thenReturn(
      const AuthAuthenticated(
        userId: 'user-1',
        isOnboarded: true,
        isVaultLocked: false,
      ),
    );
    final preferences = _Preferences();
    final theme = ThemeCubit(preferences);
    final locale = LocaleCubit(preferences);
    addTearDown(auth.close);
    addTearDown(theme.close);
    addTearDown(locale.close);
    final scaffold = GlobalKey<ScaffoldState>();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            key: scaffold,
            endDrawer: const SettingsDrawer(),
            body: const Text('Home'),
          ),
        ),
        GoRoute(
          path: AppRoutes.settingsGeneral,
          builder: (_, _) =>
              Scaffold(appBar: AppBar(title: const Text('General details'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: auth),
          BlocProvider<ThemeCubit>.value(value: theme),
          BlocProvider<LocaleCubit>.value(value: locale),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    scaffold.currentState!.openEndDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(find.text('General details'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(scaffold.currentState!.isEndDrawerOpen, isTrue);
    expect(find.text('Team').hitTestable(), findsOneWidget);
  });

  test('settings route guard mirrors permission affordances', () {
    const noPermissions = AuthAuthenticated(
      userId: 'user-1',
      isOnboarded: true,
      permissions: 0,
    );
    const manager = AuthAuthenticated(
      userId: 'user-1',
      isOnboarded: true,
      permissions: Permissions.organizationManagement,
    );
    const administrator = AuthAuthenticated(
      userId: 'admin-1',
      isOnboarded: true,
      permissions: Permissions.administratorRoleMask,
    );

    expect(
      settingsPermissionRedirect(
        noPermissions,
        Permissions.organizationManagement,
      ),
      AppRoutes.settingsGeneral,
    );
    expect(
      settingsPermissionRedirect(
        noPermissions,
        Permissions.addUser,
        fallback: AppRoutes.settingsTeam,
      ),
      AppRoutes.settingsTeam,
    );
    expect(
      settingsPermissionRedirect(manager, Permissions.organizationManagement),
      isNull,
    );
    expect(
      settingsPermissionRedirect(
        administrator,
        Permissions.organizationManagement,
      ),
      isNull,
    );
    expect(
      settingsPermissionRedirect(administrator, Permissions.addUser),
      isNull,
    );
  });
}
