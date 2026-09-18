import 'dart:async';
import 'dart:io';
import 'package:mobile_palladin/features/privacy/data/consent_activation_store.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/core/widgets/app_toggle.dart';
import 'package:mobile_palladin/core/widgets/sheet_surface.dart';
import 'package:mobile_palladin/core/widgets/sheet_action_buttons.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/core/theme/app_spacing.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/privacy/domain/user_consent.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';
import 'privacy_sheet_harness.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_settings_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'privacy_fixture.dart';
import 'package:mobile_palladin/features/settings/presentation/pages/security_page.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_consent_sheet.dart';

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Completion extends Mock {
  void call();
}

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
  bool analyticsFails = false;
  bool failReadAfterRejection = false;
  @override
  Future<UserConsents> get(String locale, {dynamic cancelToken}) async {
    if (networkFails) throw StateError('network');
    return pendingRead == null
        ? UserConsents([current, marketing], 60)
        : pendingRead!.future;
  }

  @override
  Future<UserConsent> decide(ConsentDecision d, {dynamic cancelToken}) async {
    if (d.purpose != 'email_marketing') {
      if (analyticsFails) {
        decisions.add(d);
        throw StateError('network');
      }
      try {
        return await super.decide(d, cancelToken: cancelToken);
      } catch (_) {
        if (failReadAfterRejection) networkFails = true;
        rethrow;
      }
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
  setUpAll(() async {
    // Use Flutter's bundled font for geometric/glyph assertions. Ahem's square
    // glyphs exaggerate wrapped labels and do not represent the native UI.
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  });
  late _Remote remote;
  late ConsentCubit cubit;
  late _AuthBloc auth;
  late _Completion completed;
  setUp(() async {
    completed = _Completion();
    remote = _Remote();
    cubit = ConsentCubit(remote, MemoryActivationStore(), AnalyticsService());
    await cubit.bind('account', 'en');
    auth = _AuthBloc();
    when(
      () => auth.state,
    ).thenReturn(const AuthAuthenticated(userId: 'account', isOnboarded: true));
  });
  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
    await auth.close();
  });
  Widget app(Widget page, {String locale = 'en', ThemeData? theme}) =>
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cubit),
          BlocProvider<AuthBloc>.value(value: auth),
        ],
        child: MaterialApp(
          theme: theme,
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => AppShellScope(
            openSettingsDrawer: () {},
            setBottomNavHidden: (_) {},
            setFab: (_, _) {},
            clearFab: (_) {},
            child: child!,
          ),
          home: page,
        ),
      );

  for (final viewport in [const Size(390, 1200), const Size(320, 568)]) {
    for (final startup in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'consent layout fills sheet and pins footer: $viewport startup=$startup text=$scale',
          (tester) async {
            tester.view.physicalSize = viewport;
            tester.view.devicePixelRatio = 1;
            tester.view.viewPadding = const FakeViewPadding(bottom: 34);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetViewPadding);
            addTearDown(tester.view.resetViewInsets);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await tester.pumpWidget(
              app(
                startup
                    ? PrivacySheetHarness(onCompleted: completed.call)
                    : const PrivacySettingsPage(),
                locale: 'pl',
              ),
            );
            await tester.pumpAndSettle();
            final sheet = find.byType(SheetSurface);
            final footer = find.byType(SheetActionButtons);
            final scroll = find.descendant(
              of: sheet,
              matching: find.byType(SingleChildScrollView),
            );
            Rect assertLayout() {
              final sheetRect = tester.getRect(sheet);
              final footerRect = tester.getRect(footer);
              final scrollRect = tester.getRect(scroll);
              expect(sheetRect.bottom, closeTo(viewport.height, .01));
              expect(footerRect.bottom, closeTo(sheetRect.bottom, .01));
              expect(footerRect.left, sheetRect.left);
              expect(footerRect.right, sheetRect.right);
              expect(scrollRect.bottom, closeTo(footerRect.top, .01));
              expect(scrollRect.height, greaterThan(0));
              final save = find.widgetWithText(OutlinedButton, 'Zapisz wybór');
              final accept = find.widgetWithText(
                FilledButton,
                'Akceptuj wszystkie',
              );
              expect(tester.getSize(save), tester.getSize(accept));
              for (final button in [save, accept]) {
                final labelRect = tester.getRect(
                  find.descendant(of: button, matching: find.byType(Text)),
                );
                final buttonRect = tester.getRect(button);
                expect(labelRect.top, greaterThanOrEqualTo(buttonRect.top));
                expect(labelRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(of: button, matching: find.byType(RichText)),
                );
                for (final box in paragraph.getBoxesForSelection(
                  TextSelection(
                    baseOffset: 0,
                    extentOffset: paragraph.text.toPlainText().length,
                  ),
                )) {
                  expect(
                    paragraph.localToGlobal(Offset(box.left, box.top)).dy,
                    greaterThanOrEqualTo(buttonRect.top),
                  );
                  expect(
                    paragraph.localToGlobal(Offset(box.right, box.bottom)).dy,
                    lessThanOrEqualTo(buttonRect.bottom),
                  );
                }
              }
              expect(save.hitTestable(), findsOneWidget);
              expect(accept.hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
              return footerRect;
            }

            final initialFooter = assertLayout();
            for (final toggle in find.byType(AppToggle).evaluate()) {
              final target = find
                  .ancestor(
                    of: find.byWidget(toggle.widget),
                    matching: find.byType(InkWell),
                  )
                  .first;
              final card = find
                  .ancestor(
                    of: target,
                    matching: find.byWidgetPredicate(
                      (w) => w is Container && w.decoration is BoxDecoration,
                    ),
                  )
                  .first;
              expect(
                tester.getRect(target).right,
                closeTo(
                  tester.getRect(card).right - AppSpacing.cardPadding - 1,
                  .01,
                ),
              );
            }

            // Every intermediate frame must keep the footer pinned, not just
            // the final collapsed/expanded sizes (a numeric layout golden).
            for (final tile in find.byType(ExpansionTile).evaluate().toList()) {
              final title = find.descendant(
                of: find.byWidget(tile.widget),
                matching: find.byType(ListTile),
              );
              await tester.ensureVisible(title);
              await tester.tap(title);
              for (var frame = 0; frame < 5; frame++) {
                await tester.pump(const Duration(milliseconds: 50));
                expect(assertLayout(), initialFooter);
              }
              await tester.pumpAndSettle();
              expect(assertLayout(), initialFooter);
            }
            final scrollable = tester.state<ScrollableState>(
              find
                  .descendant(of: scroll, matching: find.byType(Scrollable))
                  .first,
            );
            scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(assertLayout(), initialFooter);
            if (viewport.height < 600) {
              expect(scrollable.position.maxScrollExtent, greaterThan(0));
            }
            // The shared footer owns the keyboard/safe-area inset once.
            tester.view.viewInsets = const FakeViewPadding(bottom: 180);
            await tester.pumpAndSettle();
            assertLayout();
            final acceptRect = tester.getRect(
              find.widgetWithText(FilledButton, 'Akceptuj wszystkie'),
            );
            expect(acceptRect.bottom, lessThanOrEqualTo(viewport.height - 180));
            tester.view.resetViewInsets();
            await tester.pumpAndSettle();
            expect(assertLayout(), initialFooter);
            expect(remote.decisions, isEmpty);
            expect(cubit.state.locallyActive, isFalse);
          },
        );
      }
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'consent details have local borderless themes and retain keyboard actions: $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final theme = ThemeData(
          brightness: brightness,
          dividerColor: AppColors.brandRed,
          expansionTileTheme: const ExpansionTileThemeData(
            shape: Border(top: BorderSide(color: AppColors.brandRed)),
            collapsedShape: Border(
              bottom: BorderSide(color: AppColors.brandRed),
            ),
          ),
        );
        await tester.pumpWidget(app(const PrivacySettingsPage(), theme: theme));
        await tester.pumpAndSettle();
        final footer = find.byType(SheetActionButtons);
        final footerPosition = tester.getTopLeft(footer);
        expect(
          Theme.of(tester.element(footer)).dividerColor,
          theme.dividerColor,
        );
        final footerContainer = tester.widget<Container>(
          find.descendant(of: footer, matching: find.byType(Container)).first,
        );
        final footerBorder =
            (footerContainer.decoration! as BoxDecoration).border! as Border;
        expect(footerBorder.top.color, AppColors.cardBorder(brightness));
        expect(footerBorder.top.style, BorderStyle.solid);

        final tiles = find.byType(ExpansionTile);
        expect(tiles, findsNWidgets(2));
        for (var index = 0; index < 2; index++) {
          final tile = tiles.at(index);
          final context = tester.element(tile);
          final localTheme = Theme.of(context);
          expect(localTheme.dividerColor, AppColors.transparent);
          expect(localTheme.focusColor, theme.focusColor);
          final tileTheme = ExpansionTileTheme.of(context);
          expect(tileTheme.shape, const Border());
          expect(tileTheme.collapsedShape, const Border());
          final card = tester.widget<Container>(
            find
                .ancestor(
                  of: tile,
                  matching: find.byWidgetPredicate(
                    (w) => w is Container && w.decoration is BoxDecoration,
                  ),
                )
                .first,
          );
          final border = (card.decoration! as BoxDecoration).border! as Border;
          expect(border, Border.all(color: AppColors.navBorder(brightness)));
          final title = find.descendant(
            of: tile,
            matching: find.text('Consent details'),
          );
          await tester.ensureVisible(title);
          await tester.tap(title);
          await tester.pumpAndSettle();
          final notice = index == 0
              ? remote.current.currentNotice!.text
              : remote.marketing.currentNotice!.text;
          expect(find.text(notice), findsOneWidget);
          final focus = Focus.of(tester.element(title));
          focus.requestFocus();
          await tester.pump();
          expect(focus.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.text(notice), findsNothing);
        }
        expect(tester.getTopLeft(footer), footerPosition);
        expect(
          tester
              .widgetList<AppToggle>(find.byType(AppToggle))
              .map((t) => t.value),
          [false, false],
        );
        expect(remote.decisions, isEmpty);
        expect(cubit.state.locallyActive, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'startup is a modal sheet, optional off and essential always active; dismissal makes no decision',
    (tester) async {
      await tester.pumpWidget(
        app(PrivacySheetHarness(onCompleted: completed.call)),
      );
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
      verify(() => completed()).called(1);
      expect(remote.decisions, isEmpty);
    },
  );

  for (final locale in ['en', 'pl']) {
    for (final startup in [true, false]) {
      testWidgets(
        'shared surface and immediately enabled outlined Save denies both untouched choices: $locale startup=$startup',
        (tester) async {
          tester.view.physicalSize = const Size(390, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            app(
              startup
                  ? PrivacySheetHarness(onCompleted: completed.call)
                  : const PrivacySettingsPage(),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SheetSurface), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(PrivacySettingsPage),
              matching: find.byType(AppToggle),
            ),
            findsNothing,
          );
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(
            find.text(
              locale == 'pl' ? 'Marketing e-mailowy' : 'Email marketing',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              locale == 'pl'
                  ? 'Nowości i oferty Palladin e-mailem.'
                  : 'Palladin news and offers by email.',
            ),
            findsOneWidget,
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
          expect(
            find.text(
              locale == 'pl'
                  ? 'Opcjonalne pomiary korzystania z funkcji aplikacji.'
                  : 'Optional measurements of how you use app features.',
            ),
            findsOneWidget,
          );
          final save = find.widgetWithText(
            OutlinedButton,
            locale == 'pl' ? 'Zapisz wybór' : 'Save choice',
          );
          final accept = find.widgetWithText(
            FilledButton,
            locale == 'pl' ? 'Akceptuj wszystkie' : 'Accept all',
          );
          final primary = tester.widget<FilledButton>(accept);
          expect(primary.onPressed, isNotNull);
          expect(
            primary.style!.backgroundColor!.resolve({}),
            AppColors.brandRed,
          );
          expect(tester.widget<OutlinedButton>(save).onPressed, isNotNull);
          expect(
            find.descendant(
              of: find.byType(SheetActionButtons),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            ),
            findsNWidgets(2),
          );
          expect(tester.getSize(save).height, 44);
          expect(tester.getSize(save), tester.getSize(accept));
          for (final button in [save, accept]) {
            final labelRect = tester.getRect(
              find.descendant(of: button, matching: find.byType(Text)),
            );
            final buttonRect = tester.getRect(button);
            expect(labelRect.top, greaterThanOrEqualTo(buttonRect.top));
            expect(labelRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: button, matching: find.byType(RichText)),
            );
            for (final box in paragraph.getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: paragraph.text.toPlainText().length,
              ),
            )) {
              expect(
                paragraph.localToGlobal(Offset(box.left, box.top)).dy,
                greaterThanOrEqualTo(buttonRect.top),
              );
              expect(
                paragraph.localToGlobal(Offset(box.right, box.bottom)).dy,
                lessThanOrEqualTo(buttonRect.bottom),
              );
            }
          }
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(remote.decisions.map((d) => [d.purpose, d.granted]), [
            ['product_analytics', false],
            ['email_marketing', false],
          ]);
          expect(cubit.state.locallyActive, isFalse);
          if (!startup) {
            expect(find.byType(BottomSheet), findsNothing);
            expect(find.byType(AppToggle), findsNothing);
            expect(
              find.text(locale == 'pl' ? 'Bezpieczeństwo' : 'Security'),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'direct privacy entry reveals Security after close/back; explicit reopen never stacks sheets',
    (tester) async {
      await tester.pumpWidget(app(const PrivacySettingsPage()));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(AppToggle), findsNothing);
      unawaited(
        showPrivacyConsentSheet(
          tester.element(find.byType(SecurityPage)),
          source: 'mobile_settings',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(SecurityPage), findsOneWidget);
      expect(remote.decisions, isEmpty);
      verifyNever(() => completed());
      unawaited(
        showPrivacyConsentSheet(
          tester.element(find.byType(SecurityPage)),
          source: 'mobile_settings',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    },
  );

  testWidgets(
    'settings route pops back to its navigation origin after closing the sheet',
    (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PrivacySettingsPage(),
                  ),
                ),
                child: const Text('Settings origin'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Settings origin'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(SecurityPage), findsOneWidget);
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Settings origin'), findsOneWidget);
      expect(find.byType(AppToggle), findsNothing);
      expect(remote.decisions, isEmpty);
    },
  );

  testWidgets(
    'settings Close and Back stay closed to dismissal throughout post-save refresh',
    (tester) async {
      await tester.pumpWidget(app(const PrivacySettingsPage()));
      await tester.pumpAndSettle();
      final refresh = Completer<UserConsents>();
      remote.pendingRead = refresh;
      await tester.tap(find.text('Save choice'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        cubit.state.saving,
        isFalse,
      ); // API finished; the form is still saving its refresh/remainder.
      await tester.tap(find.byTooltip('Close'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .maybePop();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(BottomSheet), findsOneWidget);
      remote.pendingRead = null;
      refresh.complete(UserConsents([remote.current, remote.marketing], 60));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(remote.decisions.map((d) => d.granted), [false, false]);
    },
  );

  testWidgets(
    'empty notices disable both actions and never fabricate denials',
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
      await tester.pumpWidget(
        app(PrivacySheetHarness(onCompleted: completed.call)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Save choice'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(remote.decisions, isEmpty);
      expect(cubit.state.locallyActive, isFalse);
    },
  );

  testWidgets(
    'startup Save commits both draft choices and activates this installation',
    (tester) async {
      await tester.pumpWidget(
        app(PrivacySheetHarness(onCompleted: completed.call)),
      );
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
      verify(() => completed()).called(1);
    },
  );

  for (final locale in ['en', 'pl']) {
    for (final startup in [true, false]) {
      testWidgets(
        'Accept all confirms both and activates locally: $locale startup=$startup',
        (tester) async {
          await tester.pumpWidget(
            app(
              startup
                  ? PrivacySheetHarness(onCompleted: completed.call)
                  : const PrivacySettingsPage(),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widgetList<AppToggle>(find.byType(AppToggle))
                .map((t) => t.value),
            [false, false],
          );
          await tester.tap(
            find.text(locale == 'pl' ? 'Akceptuj wszystkie' : 'Accept all'),
          );
          await tester.pumpAndSettle();
          expect(remote.decisions.map((d) => [d.purpose, d.granted]), [
            ['email_marketing', true],
            ['product_analytics', true],
          ]);
          expect(cubit.state.locallyActive, isTrue);
          expect(find.byType(BottomSheet), findsNothing);
        },
      );
    }
  }

  for (final purpose in ['product_analytics', 'email_marketing']) {
    testWidgets('Accept all disabled when $purpose notice missing', (
      tester,
    ) async {
      final missing = UserConsent(
        purpose: purpose,
        scope: 'test',
        status: 'unknown',
        revision: 0,
        activationRevision: 0,
      );
      if (purpose == 'product_analytics') {
        remote.current = missing;
      } else {
        remote.marketing = missing;
      }
      await cubit.refresh();
      await tester.pumpWidget(
        app(PrivacySheetHarness(onCompleted: completed.call)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Accept all'),
            )
            .onPressed,
        isNull,
      );
      expect(remote.decisions, isEmpty);
    });
  }

  testWidgets(
    'Accept all partial failure retries only analytics and then activates locally',
    (tester) async {
      remote.analyticsFails = true;
      await tester.pumpWidget(
        app(PrivacySheetHarness(onCompleted: completed.call)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept all'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(cubit.state.locallyActive, isFalse);
      verifyNever(() => completed());
      remote.analyticsFails = false;
      await tester.ensureVisible(find.text('Retry saving'));
      await tester.tap(find.text('Retry saving'));
      await tester.pumpAndSettle();
      expect(remote.decisions.map((d) => d.purpose), [
        'email_marketing',
        'product_analytics',
        'product_analytics',
      ]);
      expect(remote.decisions[2], same(remote.decisions[1]));
      expect(cubit.state.locallyActive, isTrue);
      verify(() => completed()).called(1);
    },
  );

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

  Future<void> selectBoth(WidgetTester tester) async {
    for (final toggle in find.byType(AppToggle).evaluate().toList()) {
      final finder = find.byWidget(toggle.widget);
      await tester.ensureVisible(finder);
      await tester.tap(
        find.ancestor(of: finder, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
    }
  }

  for (final failedPurpose in ['email_marketing', 'product_analytics']) {
    testWidgets(
      'ordinary Save partial failure at $failedPurpose retries to full local activation',
      (tester) async {
        remote.marketingFails = failedPurpose == 'email_marketing';
        remote.analyticsFails = failedPurpose == 'product_analytics';
        await tester.pumpWidget(
          app(PrivacySheetHarness(onCompleted: completed.call)),
        );
        await tester.pumpAndSettle();
        await selectBoth(tester);
        await tester.tap(find.text('Save choice'));
        await tester.pumpAndSettle();
        expect(cubit.state.locallyActive, isFalse);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(remote.decisions.first.purpose, 'email_marketing');
        final failed = remote.decisions.last;
        final count = remote.decisions.length;
        verifyNever(() => completed());
        remote.marketingFails = false;
        remote.analyticsFails = false;
        remote.pending = Completer<UserConsent>();
        await tester.ensureVisible(find.text('Retry saving'));
        await tester.tap(find.text('Retry saving'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(remote.decisions[count], same(failed));
        expect(cubit.state.locallyActive, isFalse);
        expect(find.byType(BottomSheet), findsOneWidget);
        remote.current = consent(
          status: 'granted',
          revision: 1,
          activationRevision: 1,
        );
        remote.pending!.complete(remote.current);
        await tester.pumpAndSettle();
        expect(cubit.state.locallyActive, isTrue);
        expect(find.byType(BottomSheet), findsNothing);
        verify(() => completed()).called(1);
      },
    );
  }

  testWidgets(
    'reopened settings recovers load failure and enables choices despite unresolved write',
    (tester) async {
      await tester.pumpWidget(app(const PrivacySettingsPage()));
      await tester.pumpAndSettle();
      remote.networkFails = true;
      await tester.tap(find.text('Save choice'));
      await tester.pumpAndSettle();
      await cubit.refresh();
      await tester.pumpAndSettle();
      expect(cubit.state.error, ConsentErrorKind.load);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      unawaited(
        showPrivacyConsentSheet(
          tester.element(find.byType(SecurityPage)),
          source: 'mobile_settings',
        ),
      );
      await tester.pumpAndSettle();
      remote.networkFails = false;
      await tester.ensureVisible(find.text('Retry saving'));
      await tester.tap(find.text('Retry saving'));
      await tester.pumpAndSettle();
      expect(cubit.state.error, ConsentErrorKind.save);
      expect(
        tester
            .widget<SheetActionButtons>(find.byType(SheetActionButtons))
            .onCancel,
        isNotNull,
      );
      expect(
        tester
            .widget<SheetActionButtons>(find.byType(SheetActionButtons))
            .onConfirm,
        isNotNull,
      );
      expect(
        tester
            .widgetList<AppToggle>(find.byType(AppToggle))
            .every((t) => t.onChanged != null),
        isTrue,
      );
      await tester.tap(find.text('Save choice'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  for (final status in [400, 403]) {
    for (final recoverRead in [false, true]) {
      testWidgets(
        '$status retains visible save error and draft through authoritative refresh (read recovers: $recoverRead)',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(app(const PrivacySettingsPage()));
          await tester.pumpAndSettle();
          await selectBoth(tester);
          remote.current = consent(status: 'withdrawn', revision: 4);
          remote.writeStatus = status;
          remote.failReadAfterRejection = recoverRead;
          await tester.tap(find.text('Save choice'));
          await tester.pumpAndSettle();
          if (recoverRead) {
            expect(cubit.state.error, ConsentErrorKind.load);
            remote.networkFails = false;
            await tester.tap(find.text('Retry saving'));
          }
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(SheetSurface)),
          )!;
          for (var poll = 0; poll < 2; poll++) {
            expect(find.byType(BottomSheet), findsOneWidget);
            expect(find.text(l10n.privacySaveError), findsOneWidget);
            expect(find.text(l10n.privacySaved), findsNothing);
            expect(find.text('Retry saving'), findsNothing);
            expect(cubit.state.error, ConsentErrorKind.save);
            expect(cubit.state.failedDecision, isNull);
            expect(cubit.state.locallyActive, isFalse);
            expect(
              tester
                  .widgetList<AppToggle>(find.byType(AppToggle))
                  .map((t) => t.value),
              [true, true],
            );
            expect(remote.decisions.length, 2);
            await cubit.refresh();
            await tester.pumpAndSettle();
          }
          final rejected = remote.decisions.last;
          remote.writeStatus = null;
          await tester.tap(find.text('Save choice'));
          await tester.pumpAndSettle();
          expect(remote.decisions.length, 3);
          expect(remote.decisions.last.purpose, 'product_analytics');
          expect(remote.decisions.last.expectedRevision, 4);
          expect(remote.decisions.last.requestId, isNot(rejected.requestId));
          expect(cubit.state.error, isNull);
          expect(find.byType(BottomSheet), findsNothing);
        },
      );
    }
  }

  testWidgets(
    '409 discards pending form decisions and draft before explicit reconfirmation',
    (tester) async {
      await tester.pumpWidget(
        app(PrivacySheetHarness(onCompleted: completed.call)),
      );
      await tester.pumpAndSettle();
      await selectBoth(tester);
      // The other device changes analytics after this form has loaded revision 0.
      remote.current = consent(status: 'withdrawn', revision: 4);
      remote.writeStatus = 409;
      await tester.tap(find.text('Save choice'));
      await tester.pumpAndSettle();
      expect(remote.decisions.map((d) => d.purpose), [
        'email_marketing',
        'product_analytics',
      ]);
      final stale = remote.decisions.last;
      expect(stale.expectedRevision, 0);
      expect(cubit.state.failedDecision, isNull);
      expect(cubit.state.locallyActive, isFalse);
      expect(
        find.text(
          'Privacy choices changed on another device. Review the current choices and save again to confirm.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry saving'), findsNothing);
      expect(
        tester
            .widgetList<AppToggle>(find.byType(AppToggle))
            .map((t) => t.value),
        [false, true],
      );
      await cubit.refresh();
      await tester.pumpAndSettle();
      expect(remote.decisions.length, 2);
      remote.writeStatus = null;
      final toggle = find.byType(AppToggle).first;
      await tester.ensureVisible(toggle);
      await tester.tap(
        find.ancestor(of: toggle, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save choice'));
      await tester.pumpAndSettle();
      expect(remote.decisions.last.expectedRevision, 4);
      expect(remote.decisions.last.requestId, isNot(stale.requestId));
      expect(cubit.state.locallyActive, isTrue);
      verify(() => completed()).called(1);
    },
  );

  testWidgets(
    'sheet dismissal during cached activation read cannot resume capture',
    (tester) async {
      await cubit.close();
      final store = ControlledActivationStore()
        ..pendingRead = Completer()
        ..readStarted = Completer<void>();
      final analytics = AnalyticsService()
        ..configure(
          projectKey: 'test',
          host: 'https://eu.i.posthog.com',
          released: true,
        );
      cubit = ConsentCubit(remote, store, analytics);
      remote.current = consent(
        status: 'granted',
        revision: 1,
        activationRevision: 1,
      );
      final binding = cubit.bind('account', 'en');
      await store.readStarted!.future;
      await tester.pumpWidget(app(const PrivacySettingsPage()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      store.pendingRead!.complete(const ConsentActivation('test-v1', 1));
      await binding;
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(cubit.state.locallyActive, isFalse);
      expect(analytics.isInitialized, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    },
  );

  testWidgets(
    'Polish small-screen startup and settings have parity without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(PrivacySheetHarness(onCompleted: completed.call), locale: 'pl'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Twoja prywatność'), findsOneWidget);
      expect(find.text('Zawsze aktywne'), findsOneWidget);
      expect(find.text('Akceptuj wszystkie'), findsOneWidget);
      expect(find.text('Zapisz wybór'), findsOneWidget);
      expect(find.byType(AppToggle), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
