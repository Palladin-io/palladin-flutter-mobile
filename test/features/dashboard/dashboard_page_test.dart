import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/permissions.dart';
import 'package:mobile_palladin/core/utils/secure_clipboard.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/approval/domain/repositories/approval_repository.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/grant_approval_cubit.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/pending_grants_cubit.dart';
import 'package:mobile_palladin/features/audit/domain/repositories/audit_repository.dart';
import 'package:mobile_palladin/features/audit/presentation/widgets/audit_log_row.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/dashboard/domain/entities/search_result_entity.dart';
import 'package:mobile_palladin/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_permission_service.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

// ──────────────────────────────────────────────
// Mocks / fakes
// ──────────────────────────────────────────────

class _MockDashboardRepository extends Mock implements DashboardRepository {}

class _MockEntryRepository extends Mock implements EntryRepository {}

class _MockAuditRepository extends Mock implements AuditRepository {}

class _MockAgentsRepository extends Mock implements AgentsRepository {}

class _MockApprovalRepository extends Mock implements ApprovalRepository {}

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
    required super.auditRepository,
    required super.agentsRepository,
    required super.pendingGrantsCubit,
    required super.analytics,
    required super.notificationPermissionService,
  });

  final DashboardState _seed;

  /// Number of times [load] was invoked — lets a test assert the page
  /// refreshed after an action (mount = 1, a subsequent refresh = 2).
  int loadCount = 0;

  @override
  Future<void> load({bool canViewAudit = false, String? userId}) async {
    loadCount++;
    emit(_seed);
  }
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

PendingGrant _grant() => PendingGrant(
      grantId: 'g1',
      vaultId: 'v1',
      agentId: 'ag1',
      entryId: 'e1',
      agentPublicKey: 'pk',
      agentName: 'Scraper Bot',
      vaultName: 'Personal',
      isAgentRegistered: false,
      createdAt: DateTime.utc(2026, 6, 30),
    );

AuditLogEntry _auditEntry() => AuditLogEntry(
      id: 'a1',
      eventType: AuditEventType.entryCreated,
      rawEventType: 'entry.created',
      actorType: AuditActorType.user,
      actorName: 'Ada',
      entryLabel: 'GitHub token',
      createdAt: DateTime.utc(2026, 6, 30),
    );

void main() {
  late _MockDashboardRepository dashboardRepository;
  late _MockAuditRepository auditRepository;
  late _MockAgentsRepository agentsRepository;
  late _MockApprovalRepository approvalRepository;
  late _MockPendingGrantsCubit pendingGrantsCubit;
  late _MockNotificationPermissionService permissionService;
  late _MockAnalyticsService analytics;
  late _MockAuthBloc authBloc;
  late _MockEntryRepository entryRepository;

  /// The most recently created fake dashboard cubit — captured so tests can
  /// assert on [loadCount] (page refreshes).
  _FakeDashboardCubit? lastDashboardCubit;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(_grant());
  });

  setUp(() {
    dashboardRepository = _MockDashboardRepository();
    auditRepository = _MockAuditRepository();
    agentsRepository = _MockAgentsRepository();
    approvalRepository = _MockApprovalRepository();
    pendingGrantsCubit = _MockPendingGrantsCubit();
    permissionService = _MockNotificationPermissionService();
    analytics = _MockAnalyticsService();
    authBloc = _MockAuthBloc();
    entryRepository = _MockEntryRepository();
    lastDashboardCubit = null;

    when(() => dashboardRepository.globalSearch(any(),
        limit: any(named: 'limit'))).thenAnswer((_) async => const []);

    // SearchCubit is resolved per-mount from getIt (factory in real DI).
    getIt.registerFactory<SearchCubit>(
      () => SearchCubit(
        repository: dashboardRepository,
        analytics: analytics,
      ),
    );
    // The dashboard resolves the entry repository lazily for the search-row
    // copy-secret action.
    getIt.registerFactory<EntryRepository>(() => entryRepository);
    // The reject flow opens the shared DenyGrantSheet, which resolves a
    // GrantApprovalCubit (parameterized by the grant) from getIt.
    getIt.registerFactoryParam<GrantApprovalCubit, PendingGrant, void>(
      (grant, _) =>
          GrantApprovalCubit(repository: approvalRepository, grant: grant),
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
    Uint8List? privateKey,
  }) async {
    whenListen(
      authBloc,
      const Stream<AuthState>.empty(),
      initialState: AuthAuthenticated(
        userId: 'u1',
        isOnboarded: true,
        permissions: permissions,
        email: 'ada@example.com',
        privateKey: privateKey,
      ),
    );

    getIt.registerFactory<DashboardCubit>(
      () => lastDashboardCubit = _FakeDashboardCubit(
        state,
        repository: dashboardRepository,
        auditRepository: auditRepository,
        agentsRepository: agentsRepository,
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

  group('Recent Activity gating', () {
    testWidgets(
        'with AuditView + seeded logs: renders AuditLogRow and hides '
        '"Recently added"', (tester) async {
      await pumpDashboard(
        tester,
        state: DashboardLoaded(
          recentEntries: [_recent()],
          recentActivity: [_auditEntry()],
        ),
        permissions: Permissions.auditView,
      );

      expect(find.text('Recent Activity'), findsOneWidget);
      expect(find.byType(AuditLogRow), findsOneWidget);
      expect(find.text('Recently added / modified'), findsNothing);
    });

    testWidgets(
        'without AuditView: hides "Recent Activity" and shows '
        '"Recently added"', (tester) async {
      await pumpDashboard(
        tester,
        state: DashboardLoaded(
          recentEntries: [_recent()],
          recentActivity: const [],
        ),
        permissions: 0,
      );

      expect(find.text('Recent Activity'), findsNothing);
      expect(find.byType(AuditLogRow), findsNothing);
      expect(find.text('Recently added / modified'), findsOneWidget);
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

  group('search result reveal + copy', () {
    const entryHit = SearchResultEntity(
      type: SearchResultType.entry,
      id: 'e1',
      name: 'Stripe',
      vaultId: 'v1',
      vaultName: 'Personal',
    );

    /// Stubs an entry search hit + its decrypt, pumps the dashboard, and
    /// drives the field into a live [SearchResults] state with the hit shown.
    Future<void> pumpWithEntryHit(WidgetTester tester) async {
      when(() => dashboardRepository.globalSearch(any(),
          limit: any(named: 'limit'))).thenAnswer((_) async => [entryHit]);

      when(() => entryRepository.revealEntry(
            vaultId: any(named: 'vaultId'),
            entryId: any(named: 'entryId'),
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
          )).thenAnswer(
        (_) async => RevealedEntry(
          entry: EntryEntity(
            id: 'e1',
            vaultId: 'v1',
            label: 'Stripe',
            type: EntryType.credential,
            createdAt: DateTime.utc(2026, 6, 1),
            updatedAt: DateTime.utc(2026, 6, 1),
          ),
          payload: const {'username': 'ada', 'password': 's3cr3t'},
        ),
      );

      await pumpDashboard(
        tester,
        state: const DashboardLoaded(),
        permissions: 0,
        privateKey: Uint8List.fromList([1, 2, 3, 4]),
      );

      await tester.enterText(find.byType(TextField), 'stripe');
      await tester.pump(); // focus + query
      await tester.pump(const Duration(milliseconds: 300)); // debounce fires
      await tester.pump(); // globalSearch resolves → SearchResults

      expect(find.text('Stripe'), findsOneWidget);
    }

    testWidgets(
        "tapping an entry hit's copy action decrypts + copies the secret "
        'without navigating', (tester) async {
      final clipboardCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpWithEntryHit(tester);

      // Tap the trailing copy action (not the row) — must not navigate.
      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump(); // spinner
      await tester.pump(); // revealEntry resolves + clipboard write

      verify(() => entryRepository.revealEntry(
            vaultId: 'v1',
            entryId: 'e1',
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
          )).called(1);
      expect(clipboardCalls, hasLength(1));
      expect((clipboardCalls.single.arguments as Map)['text'], 's3cr3t');

      // Drain SecureClipboard's auto-clear timer so it isn't left pending.
      await tester.pump(SecureClipboard.defaultClearAfter + const Duration(seconds: 1));
    });

    testWidgets(
        "tapping an entry hit's eye action expands a panel with the "
        'decrypted secret (row unchanged); a second tap collapses it',
        (tester) async {
      await pumpWithEntryHit(tester);

      // Before reveal: no panel, the secret is not shown anywhere.
      expect(find.text('s3cr3t'), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump(); // spinner
      await tester.pump(); // revealEntry resolves → panel populated
      await tester.pumpAndSettle(); // expand animation

      // The secret is now shown in the expanded panel, and the row itself is
      // unchanged — the name + vault-name subtitle are both still present.
      expect(find.text('s3cr3t'), findsOneWidget);
      expect(find.text('Stripe'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      verify(() => entryRepository.revealEntry(
            vaultId: 'v1',
            entryId: 'e1',
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
          )).called(1);

      // A second tap collapses the panel — the secret disappears.
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();
      expect(find.text('s3cr3t'), findsNothing);
      expect(find.text('Personal'), findsOneWidget);
    });
  });

  group('pending approvals badge', () {
    testWidgets('shows the real pending count, not a hardcoded "1"',
        (tester) async {
      await pumpDashboard(
        tester,
        state: DashboardUnknownAgent(grant: _grant(), pendingCount: 3),
        permissions: 0,
      );

      expect(find.text('Pending Approvals'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });
  });

  group('reject unknown-agent request', () {
    testWidgets(
        'tapping Reject opens the deny sheet; confirming calls denyGrant '
        'and refreshes the dashboard', (tester) async {
      when(() => approvalRepository.denyGrant(
            grant: any(named: 'grant'),
            reason: any(named: 'reason'),
          )).thenAnswer((_) async {});

      await pumpDashboard(
        tester,
        state: DashboardUnknownAgent(grant: _grant(), pendingCount: 1),
        permissions: 0,
      );
      // Mounted once → load() called a single time so far.
      expect(lastDashboardCubit!.loadCount, 1);

      // Tap the card's Reject CTA → the shared deny sheet opens.
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      expect(find.text('Deny Scraper Bot?'), findsOneWidget);

      // Confirm the denial.
      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();

      verify(() => approvalRepository.denyGrant(
            grant: any(named: 'grant'),
            reason: any(named: 'reason'),
          )).called(1);
      // Confirmation snackbar + a refresh (load called again).
      expect(find.text('Request rejected'), findsOneWidget);
      expect(lastDashboardCubit!.loadCount, 2);
    });
  });
}
