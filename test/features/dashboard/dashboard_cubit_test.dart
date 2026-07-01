import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/pending_grants_cubit.dart';
import 'package:mobile_palladin/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_permission_service.dart';

// ──────────────────────────────────────────────
// Mocks
// ──────────────────────────────────────────────

class MockDashboardRepository extends Mock implements DashboardRepository {}

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
  late MockPendingGrantsCubit pendingGrantsCubit;
  late MockNotificationPermissionService permissionService;
  late MockAnalyticsService analytics;

  setUp(() async {
    // Provide a clean SharedPreferences store for each test so pref state
    // from one test does not bleed into the next.
    SharedPreferences.setMockInitialValues({});

    repository = MockDashboardRepository();
    pendingGrantsCubit = MockPendingGrantsCubit();
    permissionService = MockNotificationPermissionService();
    analytics = MockAnalyticsService();

    // Shared happy-path stubs — individual tests can override.
    when(() => repository.getOnboardingStatus())
        .thenAnswer((_) async => _incompleteStatus);
    when(() => repository.getRecentEntries(any()))
        .thenAnswer((_) async => const []);
    when(() => pendingGrantsCubit.refresh()).thenAnswer((_) async {});
    when(() => pendingGrantsCubit.state)
        .thenReturn(const PendingGrantsState());
    when(() => analytics.capture(any(), any()))
        .thenAnswer((_) async {});

    // Default: permission not yet determined (fresh install / first prompt).
    when(() => permissionService.checkStatus()).thenAnswer(
      (_) async => NotificationPermissionStatus.notDetermined,
    );
  });

  DashboardCubit buildCubit() => DashboardCubit(
        repository: repository,
        pendingGrantsCubit: pendingGrantsCubit,
        analytics: analytics,
        notificationPermissionService: permissionService,
      );

  // ── load() ──────────────────────────────────

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
            .having(
                (s) => s.notificationPermissionDenied, 'denied', isFalse),
      ],
    );

    blocTest<DashboardCubit, DashboardState>(
      'auto-completes step when OS permission is already authorized',
      setUp: () => when(() => permissionService.checkStatus())
          .thenAnswer((_) async => NotificationPermissionStatus.authorized),
      build: buildCubit,
      act: (c) => c.load(),
      expect: () => [
        isA<DashboardLoading>(),
        isA<DashboardOnboarding>()
            .having((s) => s.notificationStepDone, 'stepDone', isTrue)
            .having(
                (s) => s.notificationPermissionDenied, 'denied', isFalse),
      ],
    );

    blocTest<DashboardCubit, DashboardState>(
      'sets denied=true when OS permission is denied',
      setUp: () => when(() => permissionService.checkStatus())
          .thenAnswer((_) async => NotificationPermissionStatus.denied),
      build: buildCubit,
      act: (c) => c.load(),
      expect: () => [
        isA<DashboardLoading>(),
        isA<DashboardOnboarding>()
            .having((s) => s.notificationStepDone, 'stepDone', isFalse)
            .having(
                (s) => s.notificationPermissionDenied, 'denied', isTrue),
      ],
    );
  });

  // ── enableNotifications() ───────────────────

  group('enableNotifications()', () {
    blocTest<DashboardCubit, DashboardState>(
      'marks step done and fires analytics when OS grants permission',
      setUp: () {
        when(() => permissionService.requestPermission()).thenAnswer(
          (_) async => NotificationPermissionStatus.authorized,
        );
      },
      build: buildCubit,
      seed: () => const DashboardOnboarding(
        status: _incompleteStatus,
        notificationStepDone: false,
      ),
      act: (c) => c.enableNotifications(),
      expect: () => [
        isA<DashboardOnboarding>()
            .having((s) => s.notificationStepDone, 'stepDone', isTrue),
      ],
      verify: (_) {
        verify(() => analytics.capture(
              'identity',
              'onboarding-notifications-enabled',
            )).called(1);
        verifyNever(() => permissionService.openSettings());
      },
    );

    blocTest<DashboardCubit, DashboardState>(
      'opens system settings and marks denied flag when OS denies permission',
      setUp: () {
        when(() => permissionService.requestPermission()).thenAnswer(
          (_) async => NotificationPermissionStatus.denied,
        );
        when(() => permissionService.openSettings())
            .thenAnswer((_) async {});
      },
      build: buildCubit,
      seed: () => const DashboardOnboarding(
        status: _incompleteStatus,
        notificationStepDone: false,
      ),
      act: (c) => c.enableNotifications(),
      expect: () => [
        isA<DashboardOnboarding>()
            .having((s) => s.notificationStepDone, 'stepDone', isFalse)
            .having(
                (s) => s.notificationPermissionDenied, 'denied', isTrue),
      ],
      verify: (_) {
        verify(() => permissionService.openSettings()).called(1);
        verify(() => analytics.capture(
              'identity',
              'onboarding-notifications-settings-opened',
            )).called(1);
        verifyNever(() => analytics.capture(
              'identity',
              'onboarding-notifications-enabled',
            ));
      },
    );

    blocTest<DashboardCubit, DashboardState>(
      'emits no state change when dialog is dismissed (notDetermined)',
      setUp: () {
        when(() => permissionService.requestPermission()).thenAnswer(
          (_) async => NotificationPermissionStatus.notDetermined,
        );
      },
      build: buildCubit,
      seed: () => const DashboardOnboarding(
        status: _incompleteStatus,
        notificationStepDone: false,
      ),
      act: (c) => c.enableNotifications(),
      expect: () => const <DashboardState>[],
      verify: (_) {
        verifyNever(() => permissionService.openSettings());
        verifyNever(
          () => analytics.capture(
            'identity',
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
      act: (c) => c.skipNotificationStep(),
      expect: () => [
        isA<DashboardOnboarding>()
            .having((s) => s.notificationStepDone, 'stepDone', isTrue),
      ],
      verify: (_) {
        verifyNever(() => permissionService.requestPermission());
        verifyNever(() => permissionService.openSettings());
      },
    );
  });
}
