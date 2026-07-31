import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/pending_grants_cubit.dart';
import 'package:mobile_palladin/features/audit/domain/repositories/audit_repository.dart';
import 'package:mobile_palladin/features/audit/presentation/audit_presentation_resolver.dart';
import 'package:mobile_palladin/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_permission_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_members_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

class MockDashboardRepository extends Mock implements DashboardRepository {}

class MockAuditRepository extends Mock implements AuditRepository {}

class MockAgentsRepository extends Mock implements AgentsRepository {}

class MockVaultListCubit extends Mock implements VaultListCubit {
  VaultListState current = const VaultListLoaded([]);

  @override
  VaultListState get state => current;
}

class MockMemberIndex extends Mock implements MemberIndexReader {}

class MockVaultMembersRepository extends Mock
    implements VaultMembersRepository {}

class MockPendingGrantsCubit extends Mock implements PendingGrantsCubit {}

class MockNotificationPermissionService extends Mock
    implements NotificationPermissionService {}

class MockAnalyticsService extends Mock implements AnalyticsService {}

// ──────────────────────────────────────────────
// Fixtures
// ──────────────────────────────────────────────

/// A minimal onboarding status where setup is NOT yet complete.
const _incompleteStatus = OnboardingStatus(
  isOnboarded: true,
  entryCreated: false,
  apiKeyCreated: false,
  agentEnrolled: false,
);

// ──────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────

void main() {
  // Platform channels (SharedPreferences, analytics) need the Flutter
  // binding initialised before the first test runs.
  setUpAll(() {
    WidgetsFlutterBinding.ensureInitialized();
  });

  late MockDashboardRepository repository;
  late MockAuditRepository auditRepository;
  late MockAgentsRepository agentsRepository;
  late MockVaultListCubit vaultListCubit;
  late MockMemberIndex memberIndex;
  late MockVaultMembersRepository vaultMembersRepository;
  late AuditPresentationResolver auditPresentationResolver;
  late MockPendingGrantsCubit pendingGrantsCubit;
  late MockNotificationPermissionService permissionService;
  late MockAnalyticsService analytics;

  setUp(() async {
    // Provide a clean SharedPreferences store for each test so pref state
    // from one test does not bleed into the next.
    SharedPreferences.setMockInitialValues({});

    repository = MockDashboardRepository();
    auditRepository = MockAuditRepository();
    agentsRepository = MockAgentsRepository();
    vaultListCubit = MockVaultListCubit();
    memberIndex = MockMemberIndex();
    vaultMembersRepository = MockVaultMembersRepository();
    auditPresentationResolver = LocalAuditPresentationResolver(
      agentsRepository: agentsRepository,
      vaultListCubit: vaultListCubit,
      vaultMembersRepository: vaultMembersRepository,
      memberIndex: memberIndex,
    );
    pendingGrantsCubit = MockPendingGrantsCubit();
    permissionService = MockNotificationPermissionService();
    analytics = MockAnalyticsService();

    // Shared happy-path stubs — individual tests can override.
    when(
      () => repository.getOnboardingStatus(),
    ).thenAnswer((_) async => _incompleteStatus);
    when(
      () => repository.getRecentEntries(any()),
    ).thenAnswer((_) async => const []);
    when(() => agentsRepository.listAgents()).thenAnswer((_) async => const []);
    when(() => memberIndex.waitForCurrent(any())).thenAnswer((_) async {});
    when(() => memberIndex.entries(any())).thenReturn(const []);
    when(
      () => vaultMembersRepository.list(any()),
    ).thenAnswer((_) async => const []);
    when(() => pendingGrantsCubit.refresh()).thenAnswer((_) async {});
    when(() => pendingGrantsCubit.state).thenReturn(const PendingGrantsState());
    when(() => analytics.capture(any(), any())).thenAnswer((_) async {});

    // Default: permission not yet determined (fresh install / first prompt).
    when(
      () => permissionService.checkStatus(),
    ).thenAnswer((_) async => NotificationPermissionStatus.notDetermined);
  });

  DashboardCubit buildCubit({Stream<String>? entryNameUpdates}) =>
      DashboardCubit(
        repository: repository,
        auditRepository: auditRepository,
        auditPresentationResolver: auditPresentationResolver,
        pendingGrantsCubit: pendingGrantsCubit,
        analytics: analytics,
        notificationPermissionService: permissionService,
        recentActivityEntryNameUpdates: entryNameUpdates,
      );

  // ── load() ──────────────────────────────────

  group('load() — Recent Activity presentation', () {
    test(
      'resolves an Entry label when the relevant MemberIndex becomes ready',
      () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_skipped:user-a': true,
        });
        vaultListCubit.current = VaultListLoaded([
          VaultEntity(
            id: 'vault-1',
            name: 'Personal',
            grantMode: GrantMode.granular,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            entryCount: 1,
            activeGrantCount: 0,
            memberCount: 1,
          ),
        ]);
        var indexReady = false;
        when(() => memberIndex.entries('vault-1')).thenAnswer(
          (_) => indexReady
              ? const [
                  MemberIndexEntry(
                    entryId: 'entry-1',
                    entryType: 1,
                    memberLabel: 'GitHub token',
                    searchFields: [],
                    revision: '1',
                    state: MemberEntryState.active,
                  ),
                ]
              : const [],
        );
        when(
          () => auditRepository.listOrgLogs(
            actions: any(named: 'actions'),
            vaultId: any(named: 'vaultId'),
            agentId: any(named: 'agentId'),
            userId: any(named: 'userId'),
            entryId: any(named: 'entryId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => AuditLogPage(
            entries: [
              AuditLogEntry(
                id: 'audit-1',
                eventType: AuditEventType.entryCreated,
                rawEventType: 'entry.created',
                actorType: AuditActorType.user,
                createdAt: DateTime.utc(2026),
                vaultId: 'vault-1',
                entryId: 'entry-1',
              ),
            ],
          ),
        );

        final indexUpdates = StreamController<String>();
        final cubit = buildCubit(entryNameUpdates: indexUpdates.stream);
        await cubit.load(canViewAudit: true, userId: 'user-a');

        var loaded = cubit.state as DashboardLoaded;
        expect(loaded.recentActivity.single.entryLabel, isNull);

        final refreshed = expectLater(
          cubit.stream,
          emits(
            isA<DashboardLoaded>().having(
              (state) => state.recentActivity.single.entryLabel,
              'entry label',
              'GitHub token',
            ),
          ),
        );
        indexReady = true;
        indexUpdates.add('vault-1');
        await refreshed;

        loaded = cubit.state as DashboardLoaded;
        expect(loaded.recentActivity.single.entryLabel, 'GitHub token');
        expect(loaded.recentActivity.single.resolvedObjectName, 'GitHub token');

        final removed = expectLater(
          cubit.stream,
          emits(
            isA<DashboardLoaded>().having(
              (state) => state.recentActivity.single.entryLabel,
              'removed entry label',
              isNull,
            ),
          ),
        );
        indexReady = false;
        indexUpdates.add('vault-1');
        await removed;

        cubit.lock();
        expect(cubit.state, isA<DashboardInitial>());
        indexReady = true;
        indexUpdates.add('vault-1');
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state, isA<DashboardInitial>());
        verifyNever(() => vaultMembersRepository.list(any()));
        await cubit.close();
        await indexUpdates.close();
      },
    );

    test('lock invalidates an in-flight Recent Activity load', () async {
      final auditPage = Completer<AuditLogPage>();
      when(
        () => auditRepository.listOrgLogs(
          actions: any(named: 'actions'),
          vaultId: any(named: 'vaultId'),
          agentId: any(named: 'agentId'),
          userId: any(named: 'userId'),
          entryId: any(named: 'entryId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) => auditPage.future);

      final cubit = buildCubit();
      final load = cubit.load(canViewAudit: true, userId: 'user-a');
      await Future<void>.delayed(Duration.zero);
      cubit.lock();
      auditPage.complete(
        AuditLogPage(
          entries: [
            AuditLogEntry(
              id: 'audit-1',
              eventType: AuditEventType.entryCreated,
              rawEventType: 'entry.created',
              actorType: AuditActorType.user,
              createdAt: DateTime.utc(2026),
              vaultId: 'vault-1',
              entryId: 'entry-1',
            ),
          ],
        ),
      );
      await load;

      expect(cubit.state, isA<DashboardInitial>());
      await cubit.close();
    });
  });

  group('load() — notification permission status', () {
    blocTest<DashboardCubit, DashboardState>(
      'emits DashboardOnboarding with stepDone=false, denied=false '
      'when permission is notDetermined',
      build: buildCubit,
      act: (c) => c.load(),
      expect: () => [
        isA<DashboardLoading>(),
        isA<DashboardOnboarding>()
            .having((s) => s.notificationStepDone, 'stepDone', isFalse)
            .having((s) => s.notificationPermissionDenied, 'denied', isFalse),
      ],
    );

    blocTest<DashboardCubit, DashboardState>(
      'auto-completes step when OS permission is already authorized',
      setUp: () => when(
        () => permissionService.checkStatus(),
      ).thenAnswer((_) async => NotificationPermissionStatus.authorized),
      build: buildCubit,
      act: (c) => c.load(),
      expect: () => [
        isA<DashboardLoading>(),
        isA<DashboardOnboarding>()
            .having((s) => s.notificationStepDone, 'stepDone', isTrue)
            .having((s) => s.notificationPermissionDenied, 'denied', isFalse),
      ],
    );

    blocTest<DashboardCubit, DashboardState>(
      'sets denied=true when OS permission is denied',
      setUp: () => when(
        () => permissionService.checkStatus(),
      ).thenAnswer((_) async => NotificationPermissionStatus.denied),
      build: buildCubit,
      act: (c) => c.load(),
      expect: () => [
        isA<DashboardLoading>(),
        isA<DashboardOnboarding>()
            .having((s) => s.notificationStepDone, 'stepDone', isFalse)
            .having((s) => s.notificationPermissionDenied, 'denied', isTrue),
      ],
    );
  });

  // ── enableNotifications() ───────────────────

  group('enableNotifications()', () {
    blocTest<DashboardCubit, DashboardState>(
      'marks step done and fires analytics when OS grants permission',
      setUp: () {
        when(
          () => permissionService.requestPermission(),
        ).thenAnswer((_) async => NotificationPermissionStatus.authorized);
      },
      build: buildCubit,
      seed: () => const DashboardOnboarding(
        status: _incompleteStatus,
        notificationStepDone: false,
      ),
      act: (c) => c.enableNotifications('user-a'),
      expect: () => [
        isA<DashboardOnboarding>().having(
          (s) => s.notificationStepDone,
          'stepDone',
          isTrue,
        ),
      ],
      verify: (_) {
        verify(
          () => analytics.capture(
            'dashboard',
            'onboarding-notifications-enabled',
          ),
        ).called(1);
        verifyNever(() => permissionService.openSettings());
      },
    );

    blocTest<DashboardCubit, DashboardState>(
      'opens system settings and marks denied flag when OS denies permission',
      setUp: () {
        when(
          () => permissionService.requestPermission(),
        ).thenAnswer((_) async => NotificationPermissionStatus.denied);
        when(() => permissionService.openSettings()).thenAnswer((_) async {});
      },
      build: buildCubit,
      seed: () => const DashboardOnboarding(
        status: _incompleteStatus,
        notificationStepDone: false,
      ),
      act: (c) => c.enableNotifications('user-a'),
      expect: () => [
        isA<DashboardOnboarding>()
            .having((s) => s.notificationStepDone, 'stepDone', isFalse)
            .having((s) => s.notificationPermissionDenied, 'denied', isTrue),
      ],
      verify: (_) {
        verify(() => permissionService.openSettings()).called(1);
        verify(
          () => analytics.capture(
            'dashboard',
            'onboarding-notifications-settings-opened',
          ),
        ).called(1);
        verifyNever(
          () => analytics.capture(
            'dashboard',
            'onboarding-notifications-enabled',
          ),
        );
      },
    );

    blocTest<DashboardCubit, DashboardState>(
      'emits no state change when dialog is dismissed (notDetermined)',
      setUp: () {
        when(
          () => permissionService.requestPermission(),
        ).thenAnswer((_) async => NotificationPermissionStatus.notDetermined);
      },
      build: buildCubit,
      seed: () => const DashboardOnboarding(
        status: _incompleteStatus,
        notificationStepDone: false,
      ),
      act: (c) => c.enableNotifications('user-a'),
      expect: () => const <DashboardState>[],
      verify: (_) {
        verifyNever(() => permissionService.openSettings());
        verifyNever(
          () => analytics.capture(
            'dashboard',
            'onboarding-notifications-enabled',
          ),
        );
      },
    );
  });

  // ── skipNotificationStep() ──────────────────

  group('skipNotificationStep()', () {
    blocTest<DashboardCubit, DashboardState>(
      'marks step done without touching the OS permission APIs',
      build: buildCubit,
      seed: () => const DashboardOnboarding(
        status: _incompleteStatus,
        notificationStepDone: false,
      ),
      act: (c) => c.skipNotificationStep('user-a'),
      expect: () => [
        isA<DashboardOnboarding>().having(
          (s) => s.notificationStepDone,
          'stepDone',
          isTrue,
        ),
      ],
      verify: (_) {
        verifyNever(() => permissionService.requestPermission());
        verifyNever(() => permissionService.openSettings());
      },
    );
  });

  // ── per-account skip scoping (the bug) ──────

  group('skip flags are scoped per user (userId)', () {
    blocTest<DashboardCubit, DashboardState>(
      'user A who skipped setup: load(userId: A) HIDES onboarding',
      build: buildCubit,
      act: (c) async {
        await c.skipSetup('user-a');
        await c.load(userId: 'user-a');
      },
      skip: 1, // drop the DashboardLoaded emitted synchronously by skipSetup
      expect: () => [isA<DashboardLoading>(), isA<DashboardLoaded>()],
      verify: (_) {
        // Onboarding was hidden without consulting the backend status.
        verifyNever(() => repository.getOnboardingStatus());
      },
    );

    blocTest<DashboardCubit, DashboardState>(
      'user B (different id): load(userId: B) SHOWS onboarding even after A skipped',
      build: buildCubit,
      act: (c) async {
        await c.skipSetup('user-a');
        await c.load(userId: 'user-b');
      },
      skip: 1, // drop the DashboardLoaded emitted synchronously by skipSetup
      expect: () => [isA<DashboardLoading>(), isA<DashboardOnboarding>()],
      verify: (_) {
        // Onboarding was resolved from the backend status, not the A flag.
        verify(() => repository.getOnboardingStatus()).called(1);
      },
    );

    blocTest<DashboardCubit, DashboardState>(
      'no userId: load() SHOWS onboarding even if a device-wide flag lingers',
      setUp: () => SharedPreferences.setMockInitialValues({
        // Legacy unscoped flag from the buggy build.
        'onboarding_skipped': true,
      }),
      build: buildCubit,
      act: (c) => c.load(),
      expect: () => [isA<DashboardLoading>(), isA<DashboardOnboarding>()],
    );

    blocTest<DashboardCubit, DashboardState>(
      'notification skip is per-user: A skipped step, B still sees it pending',
      build: buildCubit,
      act: (c) async {
        // From DashboardInitial, skipNotificationStep re-emits nothing
        // (it only refreshes an already-visible DashboardOnboarding), so the
        // only states are load()'s Loading → Onboarding.
        await c.skipNotificationStep('user-a');
        await c.load(userId: 'user-b');
      },
      expect: () => [
        isA<DashboardLoading>(),
        isA<DashboardOnboarding>().having(
          (s) => s.notificationStepDone,
          'stepDone',
          isFalse,
        ),
      ],
    );
  });
}
