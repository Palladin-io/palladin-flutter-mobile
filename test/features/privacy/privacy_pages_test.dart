import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/core/widgets/app_toggle.dart';
import 'package:mobile_palladin/core/widgets/sheet_surface.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/privacy/domain/user_consent.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_onboarding_page.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_settings_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'privacy_fixture.dart';

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Remote extends Remote {
  UserConsent marketing = const UserConsent(
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
  );
  bool marketingFails = false;
  @override
  Future<UserConsents> get(String locale, {dynamic cancelToken}) async {
    if (networkFails) throw StateError('network');
    return UserConsents([current, marketing], 60);
  }

  @override
  Future<UserConsent> decide(ConsentDecision d, {dynamic cancelToken}) async {
    if (d.purpose != 'email_marketing') {
      return super.decide(d, cancelToken: cancelToken);
    }
    decisions.add(d);
    if (networkFails || marketingFails) throw StateError('network');
    marketing = UserConsent(
      purpose: marketing.purpose,
      scope: marketing.scope,
      status: d.granted ? 'granted' : 'denied',
      revision: d.expectedRevision + 1,
      activationRevision: 0,
      noticeVersion: d.noticeVersion,
      noticeLocale: d.locale,
      currentNotice: marketing.currentNotice,
    );
    return marketing;
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

  testWidgets(
    'startup is a modal sheet, optional off and essential always active; dismissal makes no decision',
    (tester) async {
      await tester.pumpWidget(app(const PrivacyOnboardingPage()));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Your privacy'), findsOneWidget);
      expect(find.text('Always active'), findsOneWidget);
      expect(
        tester
            .widgetList<AppToggle>(find.byType(AppToggle))
            .map((t) => t.value),
        [false, false],
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      verify(() => auth.add(const PrivacyChoicesCompleted())).called(1);
      expect(remote.decisions, isEmpty);
    },
  );

  for (final locale in ['en', 'pl']) {
    for (final startup in [true, false]) {
      testWidgets(
        'shared surface and immediately enabled primary Save denies both untouched choices: $locale startup=$startup',
        (tester) async {
          tester.view.physicalSize = const Size(390, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            app(
              startup
                  ? const PrivacyOnboardingPage()
                  : const PrivacySettingsPage(),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SheetSurface), findsOneWidget);
          expect(
            find.byType(BottomSheet),
            startup ? findsOneWidget : findsNothing,
          );
          expect(
            find.text(locale == 'pl' ? 'Twoja prywatność' : 'Your privacy'),
            findsOneWidget,
          );
          expect(
            tester
                .widgetList<AppToggle>(find.byType(AppToggle))
                .map((t) => t.value),
            [false, false],
          );
          final save = find.widgetWithText(
            FilledButton,
            locale == 'pl' ? 'Zapisz wybór' : 'Save choice',
          );
          final essential = find.widgetWithText(
            OutlinedButton,
            locale == 'pl' ? 'Tylko niezbędne' : 'Essential only',
          );
          final primary = tester.widget<FilledButton>(save);
          expect(primary.onPressed, isNotNull);
          expect(
            primary.style!.backgroundColor!.resolve({}),
            AppColors.brandRed,
          );
          expect(tester.widget<OutlinedButton>(essential).onPressed, isNotNull);
          expect(tester.getSize(save).height, 44);
          expect(tester.getSize(save), tester.getSize(essential));
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(remote.decisions.map((d) => [d.purpose, d.granted]), [
            ['product_analytics', false],
            ['email_marketing', false],
          ]);
          expect(cubit.state.locallyActive, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'empty notices disable primary Save and never fabricate denials',
    (tester) async {
      remote.current = const UserConsent(
        purpose: 'product_analytics',
        scope: 'palladin_web_mobile',
        status: 'unknown',
        revision: 0,
        activationRevision: 0,
      );
      remote.marketing = const UserConsent(
        purpose: 'email_marketing',
        scope: 'palladin_email_news_and_offers',
        status: 'unknown',
        revision: 0,
        activationRevision: 0,
      );
      await cubit.refresh();
      await tester.pumpWidget(app(const PrivacyOnboardingPage()));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save choice'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Essential only'));
      await tester.pumpAndSettle();
      expect(remote.decisions, isEmpty);
      expect(cubit.state.locallyActive, isFalse);
    },
  );

  testWidgets(
    'startup Save commits both draft choices and activates this installation',
    (tester) async {
      await tester.pumpWidget(app(const PrivacyOnboardingPage()));
      await tester.pumpAndSettle();
      for (final toggle in find.byType(AppToggle).evaluate().toList()) {
        await tester.ensureVisible(find.byWidget(toggle.widget));
        await tester.tap(
          find
              .ancestor(
                of: find.byWidget(toggle.widget),
                matching: find.byType(InkWell),
              )
              .first,
        );
        await tester.pumpAndSettle();
      }
      expect(remote.decisions, isEmpty);
      await tester.tap(find.text('Save choice'));
      await tester.pumpAndSettle();
      expect(remote.decisions.map((d) => d.granted), [true, true]);
      expect(cubit.state.locallyActive, isTrue);
      verify(() => auth.add(const PrivacyChoicesCompleted())).called(1);
    },
  );

  testWidgets('essential-only saves both refusals with no required opt-in', (
    tester,
  ) async {
    await tester.pumpWidget(app(const PrivacyOnboardingPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Essential only'));
    await tester.pumpAndSettle();
    expect(remote.decisions.map((d) => d.granted), [false, false]);
    expect(cubit.state.locallyActive, isFalse);
    verify(() => auth.add(const PrivacyChoicesCompleted())).called(1);
  });

  testWidgets(
    'settings keeps another installation off until explicit local activation',
    (tester) async {
      remote.current = consent(
        status: 'granted',
        revision: 1,
        activationRevision: 1,
      );
      await cubit.refresh();
      await tester.pumpWidget(app(const PrivacySettingsPage()));
      await tester.pumpAndSettle();
      expect(find.text('Off on this device'), findsOneWidget);
      await tester.ensureVisible(find.text('Enable on this device'));
      await tester.tap(find.text('Enable on this device'));
      await tester.pumpAndSettle();
      expect(cubit.state.locallyActive, isTrue);
      expect(remote.decisions.first.source, 'mobile_settings');
    },
  );

  testWidgets(
    'partial save error stays open, stops locally and retries only the failed decision',
    (tester) async {
      remote.marketingFails = true;
      await tester.pumpWidget(app(const PrivacyOnboardingPage()));
      await tester.pumpAndSettle();
      for (final toggle in find.byType(AppToggle).evaluate().toList()) {
        await tester.ensureVisible(find.byWidget(toggle.widget));
        await tester.tap(
          find
              .ancestor(
                of: find.byWidget(toggle.widget),
                matching: find.byType(InkWell),
              )
              .first,
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Save choice'));
      await tester.pumpAndSettle();
      expect(cubit.state.locallyActive, isFalse);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(remote.decisions.length, 2);
      await tester.ensureVisible(find.text('Retry saving'));
      await tester.tap(find.text('Retry saving'));
      await tester.pumpAndSettle();
      expect(remote.decisions.length, 3);
      expect(remote.decisions[1], same(remote.decisions[2]));
      verifyNever(() => auth.add(const PrivacyChoicesCompleted()));
    },
  );

  testWidgets(
    'Polish small-screen startup and settings have parity without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(const PrivacyOnboardingPage(), locale: 'pl'));
      await tester.pumpAndSettle();
      expect(find.text('Twoja prywatność'), findsOneWidget);
      expect(find.text('Zawsze aktywne'), findsOneWidget);
      expect(find.text('Tylko niezbędne'), findsOneWidget);
      expect(find.text('Zapisz wybór'), findsOneWidget);
      expect(find.byType(AppToggle), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
