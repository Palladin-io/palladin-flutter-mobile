import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/router/app_router.dart';
import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/data/services/hibp_service.dart';
import 'package:mobile_palladin/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/verify_email_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/pages/verify_email_page.dart';
import 'package:mobile_palladin/features/onboarding/data/services/default_vault_provisioner.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';
import 'package:mobile_palladin/features/onboarding/presentation/pages/onboarding_wizard_page.dart';
import 'package:mobile_palladin/features/onboarding/presentation/cubit/onboarding_cubit.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

import 'package:mobile_palladin/features/agents/presentation/bloc/agents_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_state.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_session_controller.dart';
import 'package:mobile_palladin/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:mobile_palladin/features/settings/presentation/pages/security_page.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/notification_center_cubit.dart';
import 'package:mobile_palladin/features/unlock/presentation/cubit/unlock_cubit.dart';
import 'package:mobile_palladin/features/unlock/presentation/pages/unlock_page.dart';

import '../../features/privacy/privacy_fixture.dart';

class _Hibp extends Mock implements HibpService {}

class _OnboardingCubit extends MockCubit<OnboardingState>
    implements OnboardingCubit {}

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Datasource extends Mock implements PasswordAuthRemoteDatasource {}

class _Repository extends Mock implements AuthRepository {}

class _Provisioner extends Mock implements DefaultVaultProvisioner {}

class _UnlockCubit extends MockCubit<UnlockState> implements UnlockCubit {}

class _DashboardCubit extends MockCubit<DashboardState>
    implements DashboardCubit {}

class _SearchCubit extends MockCubit<SearchState> implements SearchCubit {}

class _AgentsCubit extends MockCubit<AgentsState> implements AgentsCubit {}

class _NotificationsCubit extends MockCubit<NotificationCenterState>
    implements NotificationCenterCubit {}

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT']!;
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        File(
          '$root/bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  });
  for (final scenario in [
    (onboarded: false, locked: true, verified: false, path: '/onboarding'),
    (onboarded: true, locked: true, verified: false, path: '/unlock'),
    (onboarded: true, locked: true, verified: false, path: '/unlock'),
    (onboarded: true, locked: false, verified: false, path: '/'),
    (onboarded: true, locked: false, verified: true, path: '/'),
  ]) {
    testWidgets('real Continue resumes guards: $scenario', (tester) async {
      final fixture = await _VerificationFixture.mount(
        tester,
        onboarded: scenario.onboarded,
        locked: scenario.locked,
        verified: scenario.verified,
      );
      // The token remains intact even for an already-verified session, and
      // optional privacy cannot interrupt its anonymous verification request.
      expect(fixture.uri, fixture.destination);
      expect(find.text('Continue'), findsNothing);
      verify(
        () => fixture.datasource.verifyEmail(_VerificationFixture.token),
      ).called(1);
      fixture.verification.complete();
      await tester.pumpAndSettle();
      expect(fixture.uri, fixture.destination);
      final provisioning = Completer<void>();
      if (!scenario.locked) {
        when(
          () => fixture.provisioner.ensureFromPrivateKey(
            privateKey: fixture.privateKey,
            name: 'Personal',
          ),
        ).thenAnswer((_) => provisioning.future);
      }
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      // A successful token alone cannot bypass the refreshed session claim.
      expect(fixture.uri, fixture.destination);
      fixture.refresh.complete();
      await tester.pumpAndSettle();
      if (!scenario.locked) {
        // The refreshed claim also cannot bypass required provisioning.
        expect(fixture.uri, fixture.destination);
        expect(find.byType(DashboardPage), findsNothing);
        provisioning.complete();
        await tester.pumpAndSettle();
      }
      expect(fixture.uri.path, scenario.path);
      expect(fixture.uri.queryParameters, isEmpty);
      expect(find.byType(VerifyEmailPage), findsNothing);
      expect((fixture.auth.state as AuthAuthenticated).emailVerified, isTrue);
      expect(
        (fixture.auth.state as AuthAuthenticated).isVaultLocked,
        scenario.locked,
      );
      verify(() => fixture.repository.refreshToken()).called(1);
      if (!scenario.locked) {
        verify(
          () => fixture.provisioner.ensureFromPrivateKey(
            privateKey: fixture.privateKey,
            name: 'Personal',
          ),
        ).called(1);
      } else {
        verifyNever(
          () => fixture.provisioner.ensureFromPrivateKey(
            privateKey: any(named: 'privateKey'),
            name: any(named: 'name'),
          ),
        );
      }
      expect(find.byType(BottomSheet), findsNothing);
      if (!scenario.onboarded) {
        expect(find.byType(OnboardingWizardPage), findsOneWidget);
      } else if (scenario.locked) {
        expect(find.byType(UnlockPage), findsOneWidget);
        expect(find.byType(DashboardPage), findsNothing);
      } else {
        expect(find.byType(DashboardPage), findsOneWidget);
      }
      if (scenario.verified && !scenario.locked && scenario.onboarded) {
        fixture.router.go('/settings/privacy');
        await tester.pumpAndSettle();
        expect(find.byType(SecurityPage), findsOneWidget);
        expect(find.byType(BottomSheet), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(fixture.uri.path, '/settings/security');
        expect(find.byType(SecurityPage), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
      }
      await fixture.dispose();
    });
  }

  for (final failure in [
    'pending claim',
    'refresh failure',
    'provisioning failure',
  ]) {
    testWidgets('Continue retains verification and gates on $failure', (
      tester,
    ) async {
      final fixture = await _VerificationFixture.mount(tester);
      fixture.verification.complete();
      await tester.pumpAndSettle();
      if (failure == 'pending claim') {
        when(
          () => fixture.repository.isEmailVerified(),
        ).thenAnswer((_) async => false);
      } else if (failure == 'provisioning failure') {
        when(
          () => fixture.provisioner.ensureFromPrivateKey(
            privateKey: fixture.privateKey,
            name: 'Personal',
          ),
        ).thenThrow(StateError('fixture provisioning failure'));
      }
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(fixture.uri, fixture.destination);
      if (failure == 'refresh failure') {
        fixture.refresh.completeError(StateError('fixture refresh failure'));
      } else {
        fixture.refresh.complete();
      }
      await tester.pumpAndSettle();
      expect(fixture.uri, fixture.destination);
      expect(find.byType(VerifyEmailPage), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(DashboardPage), findsNothing);
      expect((fixture.auth.state as AuthAuthenticated).emailVerified, isFalse);
      await fixture.dispose();
    });
  }

  for (final onboarded in [false, true]) {
    testWidgets(
      'verification token reaches real cubit before optional privacy (onboarded: $onboarded)',
      (tester) async {
        await getIt.reset();
        final auth = _AuthBloc();
        when(() => auth.state).thenReturn(
          AuthAuthenticated(
            userId: 'account',
            isOnboarded: onboarded,
            emailVerified: false,
          ),
        );
        final datasource = _Datasource();
        const token = 'fixture+token/with=query';
        when(() => datasource.verifyEmail(token)).thenAnswer((_) async {});
        getIt.registerFactory<VerifyEmailCubit>(
          () => VerifyEmailCubit(
            datasource: datasource,
            authRepository: _Repository(),
            defaultVaultProvisioner: _Provisioner(),
          ),
        );
        final consents = ConsentCubit(
          Remote(),
          MemoryActivationStore(),
          AnalyticsService(),
        );
        await consents.bind('account', 'en');
        final router = createRouter(auth);
        final destination = Uri(
          path: '/verify-email',
          queryParameters: {'token': token},
        );
        router.go(destination.toString());
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider.value(value: consents),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri, destination);
        expect(
          tester.widget<VerifyEmailPage>(find.byType(VerifyEmailPage)).token,
          token,
        );
        verify(() => datasource.verifyEmail(token)).called(1);
        expect(find.byType(BottomSheet), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await auth.close();
        if (!consents.isClosed) await consents.close();
        await getIt.reset();
      },
    );
  }
}

/// Real production router, verification page/cubit and AuthBloc. Only remote
/// dependencies and unrelated destination-page cubits are stubbed.
class _VerificationFixture {
  static const token = 'fixture+token/with=query';
  final datasource = _Datasource();
  final repository = _Repository();
  final provisioner = _Provisioner();
  final verification = Completer<void>();
  final refresh = Completer<void>();
  final privateKey = Uint8List(32);
  final destination = Uri(
    path: '/verify-email',
    queryParameters: {'token': token},
  );
  late final Future<void> Function() dispose;
  late final AuthBloc auth;
  late final router = createRouter(auth);
  Uri get uri => router.routeInformationProvider.value.uri;

  static Future<_VerificationFixture> mount(
    WidgetTester tester, {
    bool onboarded = true,
    bool locked = false,
    bool verified = false,
  }) async {
    await getIt.reset();
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    registerFallbackValue(Uint8List(32));
    final f = _VerificationFixture();
    when(() => f.repository.isAuthenticated()).thenAnswer((_) async => true);
    when(() => f.repository.getUserId()).thenAnswer((_) async => 'account');
    when(() => f.repository.isOnboarded()).thenAnswer((_) async => onboarded);
    when(() => f.repository.getPermissions()).thenAnswer((_) async => 0);
    when(
      () => f.repository.getEmail(),
    ).thenAnswer((_) async => 'fixture@example.test');
    when(() => f.repository.getAuthProvider()).thenAnswer((_) async => null);
    when(
      () => f.repository.isEmailVerified(),
    ).thenAnswer((_) async => verified);
    f.auth = AuthBloc(authRepository: f.repository)
      ..add(const AuthCheckRequested());
    await f.auth.stream.firstWhere((state) => state is AuthAuthenticated);
    if (!locked) {
      f.auth.add(
        VaultUnlocked(masterKey: Uint8List(32), privateKey: f.privateKey),
      );
      await f.auth.stream.firstWhere(
        (state) => state is AuthAuthenticated && !state.isVaultLocked,
      );
    }
    when(
      () => f.datasource.verifyEmail(token),
    ).thenAnswer((_) => f.verification.future);
    when(() => f.repository.refreshToken()).thenAnswer((_) => f.refresh.future);
    when(() => f.repository.isEmailVerified()).thenAnswer((_) async => true);
    when(
      () => f.provisioner.ensureFromPrivateKey(
        privateKey: f.privateKey,
        name: 'Personal',
      ),
    ).thenAnswer((_) async {});
    getIt.registerFactory<VerifyEmailCubit>(
      () => VerifyEmailCubit(
        datasource: f.datasource,
        authRepository: f.repository,
        defaultVaultProvisioner: f.provisioner,
      ),
    );
    getIt.registerSingleton<HibpService>(_Hibp());
    final onboarding = _OnboardingCubit();
    when(() => onboarding.state).thenReturn(const OnboardingState());
    getIt.registerFactory<OnboardingCubit>(() => onboarding);
    final unlock = _UnlockCubit();
    when(() => unlock.state).thenReturn(const UnlockInitial());
    when(() => unlock.isBiometricAvailable()).thenAnswer((_) async => false);
    getIt.registerFactory<UnlockCubit>(() => unlock);
    final dashboard = _DashboardCubit();
    when(() => dashboard.state).thenReturn(const DashboardLoaded());
    when(
      () => dashboard.load(canViewAudit: false, userId: 'account'),
    ).thenAnswer((_) async {});
    getIt.registerSingleton<DashboardCubit>(dashboard);
    final search = _SearchCubit();
    when(() => search.state).thenReturn(const SearchIdle());
    getIt.registerFactory<SearchCubit>(() => search);
    getIt.registerSingleton<SearchSessionController>(SearchSessionController());
    final agents = _AgentsCubit();
    when(() => agents.state).thenReturn(const AgentsState());
    when(() => agents.refresh()).thenAnswer((_) async {});
    getIt.registerSingleton<AgentsCubit>(agents);
    final notifications = _NotificationsCubit();
    when(() => notifications.state).thenReturn(const NotificationCenterState());
    when(() => notifications.refreshSummary()).thenAnswer((_) async {});
    getIt.registerSingleton<NotificationCenterCubit>(notifications);
    final consents = ConsentCubit(
      Remote(),
      MemoryActivationStore(),
      AnalyticsService(),
    );
    await consents.bind('account', 'en');
    f.dispose = () async {
      final closing = consents.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await closing;
    };
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      f.router.dispose();
      await f.auth.close();
      if (!consents.isClosed) await consents.close();
      await dashboard.close();
      await agents.close();
      await notifications.close();
      await getIt.reset();
    });
    // This is the incoming link only. All subsequent navigation is performed
    // by the real Continue button, AuthBloc and production router guards.
    f.router.go(f.destination.toString());
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: f.auth),
          BlocProvider.value(value: consents),
        ],
        child: MaterialApp.router(
          routerConfig: f.router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    return f;
  }
}
