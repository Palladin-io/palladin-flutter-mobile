import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/permissions.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/pending_grants_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_permission_service.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

// ──────────────────────────────────────────────
// Mocks / fakes
// ──────────────────────────────────────────────

class _MockDashboardRepository extends Mock implements DashboardRepository {}

class _MockPendingGrantsCubit extends Mock implements PendingGrantsCubit {}

class _MockNotificationPermissionService extends Mock
    implements NotificationPermissionService {}

class _MockAnalyticsService extends Mock implements AnalyticsService {}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

/// A [DashboardCubit] whose [load] just emits a preset state, so a widget
/// test can drive the page into any branch without stubbing the whole
/// onboarding pipeline.
class _FakeDashboardCubit extends DashboardCubit {
  _FakeDashboardCubit(
    this._seed, {
    required super.repository,
    required super.pendingGrantsCubit,
    required super.analytics,
    required super.notificationPermissionService,
  });

  final DashboardState _seed;

  @override
  Future<void> load() async => emit(_seed);
}

// ──────────────────────────────────────────────
// Fixtures
// ──────────────────────────────────────────────

RecentEntryEntity _recent() => RecentEntryEntity(
      id: 'e1',
      label: 'GitHub token',
      vaultId: 'v1',
      vaultName: 'Personal',
      typeWire: 1,
      updatedAt: DateTime.utc(2026, 6, 30),
      createdAt: DateTime.utc(2026, 6, 1),
    );

void main() {
  late _MockDashboardRepository dashboardRepository;
  late _MockPendingGrantsCubit pendingGrantsCubit;
  late _MockNotificationPermissionService permissionService;
  late _MockAnalyticsService analytics;
  late _MockAuthBloc authBloc;

  setUp(() {
    dashboardRepository = _MockDashboardRepository();
    pendingGrantsCubit = _MockPendingGrantsCubit();
    permissionService = _MockNotificationPermissionService();
    analytics = _MockAnalyticsService();
    authBloc = _MockAuthBloc();

    when(() => dashboardRepository.globalSearch(any(),
        limit: any(named: 'limit'))).thenAnswer((_) async => const []);

    // SearchCubit is resolved per-mount from getIt (factory in real DI).
    getIt.registerFactory<SearchCubit>(
      () => SearchCubit(
        repository: dashboardRepository,
        analytics: analytics,
      ),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  /// Pumps the [DashboardPage] with [state] as the resolved dashboard state
  /// and [permissions] on the authenticated user.
  Future<void> pumpDashboard(
    WidgetTester tester, {
    required DashboardState state,
    required int permissions,
  }) async {
    whenListen(
      authBloc,
      const Stream<AuthState>.empty(),
      initialState: AuthAuthenticated(
        userId: 'u1',
        isOnboarded: true,
        permissions: permissions,
        email: 'ada@example.com',
      ),
    );

    getIt.registerFactory<DashboardCubit>(
      () => _FakeDashboardCubit(
        state,
        repository: dashboardRepository,
        pendingGrantsCubit: pendingGrantsCubit,
        analytics: analytics,
        notificationPermissionService: permissionService,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: AppShellScope(
            openSettingsDrawer: () {},
            setBottomNavHidden: (_) {},
            setFab: (_, _) {},
            clearFab: (_) {},
            child: const DashboardPage(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('Recently added / modified gating', () {
    testWidgets('shows the section when the user has NO AuditView permission',
        (tester) async {
      await pumpDashboard(
        tester,
        state: DashboardLoaded(recentEntries: [_recent()]),
        permissions: 0,
      );

      expect(find.text('Recently added / modified'), findsOneWidget);
      expect(find.text('GitHub token'), findsOneWidget);
    });

    testWidgets('hides the section when the user HAS AuditView permission',
        (tester) async {
      await pumpDashboard(
        tester,
        state: DashboardLoaded(recentEntries: [_recent()]),
        permissions: Permissions.auditView,
      );

      expect(find.text('Recently added / modified'), findsNothing);
    });
  });

  group('search dropdown', () {
    testWidgets('focusing the field opens the Recent dropdown', (tester) async {
      // AuditView hides the Home "Recently added" section, so the recent
      // entry appears only inside the dropdown (unambiguous assertion).
      await pumpDashboard(
        tester,
        state: DashboardLoaded(recentEntries: [_recent()]),
        permissions: Permissions.auditView,
      );

      // No dropdown before focus.
      expect(find.text('Recent'), findsNothing);
      expect(find.text('GitHub token'), findsNothing);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump();

      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('GitHub token'), findsOneWidget);
    });
  });
}
