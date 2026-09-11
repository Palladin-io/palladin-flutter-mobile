import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/core/widgets/app_toggle.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/privacy/domain/user_consent.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_onboarding_page.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_settings_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'privacy_fixture.dart';

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Remote extends Remote {
  @override
  Future<UserConsents> get(String locale, {dynamic cancelToken}) async {
    if (networkFails) throw StateError('network');
    return UserConsents([
      current,
      const UserConsent(
        purpose: 'email_marketing',
        scope: 'palladin_email_news_and_offers',
        status: 'unknown',
        revision: 0,
        activationRevision: 0,
        currentNotice: ConsentNotice(
          version: 'test-v1',
          locale: 'en',
          text: 'Test marketing notice',
        ),
      ),
    ], 60);
  }
}

void main() {
  late _Remote remote;
  late ConsentCubit cubit;
  late _AuthBloc auth;
  setUp(() async {
    remote = _Remote();
    cubit = ConsentCubit(remote, MemoryActivationStore(), AnalyticsService());
    await cubit.bind('account', 'en');
    auth = _AuthBloc();
    when(() => auth.state).thenReturn(
      const AuthAuthenticated(
        userId: 'account',
        isOnboarded: true,
        needsPrivacyChoices: true,
      ),
    );
  });
  tearDown(() async {
    await cubit.close();
    await auth.close();
  });
  Widget app(Widget page, {String locale = 'en'}) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: cubit),
      BlocProvider<AuthBloc>.value(value: auth),
    ],
    child: MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppShellScope(
        openSettingsDrawer: () {},
        setBottomNavHidden: (_) {},
        setFab: (_, _) {},
        clearFab: (_) {},
        child: page,
      ),
    ),
  );

  testWidgets('onboarding permits continuing with both options off', (
    tester,
  ) async {
    await tester.pumpWidget(app(const PrivacyOnboardingPage()));
    expect(
      tester
          .widgetList<AppToggle>(find.byType(AppToggle))
          .map((toggle) => toggle.value),
      [false, false],
    );
    await tester.tap(find.text('Continue'));
    verify(() => auth.add(const PrivacyChoicesCompleted())).called(1);
    expect(remote.decisions, isEmpty);
  });
  testWidgets(
    'settings grant uses the displayed notice and the settings source',
    (tester) async {
      await tester.pumpWidget(app(const PrivacySettingsPage()));
      await tester.tap(find.byType(AppToggle).first);
      await tester.pumpAndSettle();
      expect(remote.decisions.single.source, 'mobile_settings');
      expect(remote.decisions.single.noticeVersion, 'test-v1');
      expect(find.text('Privacy choice saved'), findsOneWidget);
    },
  );
  testWidgets('save failure remains visible and onboarding can continue', (
    tester,
  ) async {
    remote.networkFails = true;
    await tester.pumpWidget(app(const PrivacyOnboardingPage()));
    await tester.tap(find.byType(AppToggle).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be confirmed'), findsOneWidget);
    expect(find.text('Retry saving'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    verify(() => auth.add(const PrivacyChoicesCompleted())).called(1);
  });
  testWidgets(
    'Polish small-screen settings have both controls without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(const PrivacySettingsPage(), locale: 'pl'));
      expect(find.text('Prywatność'), findsOneWidget);
      expect(find.byType(AppToggle), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
