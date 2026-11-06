import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/presentation/autofill_guide_page.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final locale in ['en', 'pl']) {
      for (final brightness in Brightness.values) {
        testWidgets('$platform $locale $brightness remains readable at 2x', (
          tester,
        ) async {
          debugDefaultTargetPlatformOverride = platform;
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              theme: ThemeData(brightness: brightness),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: AppShellScope(
                  openSettingsDrawer: () {},
                  setBottomNavHidden: (_) {},
                  setFab: (_, _) {},
                  clearFab: (_) {},
                  child: child!,
                ),
              ),
              home: const AutofillGuidePage(),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(AutofillGuidePage)),
          )!;
          final ios = platform == TargetPlatform.iOS;
          final instructions = [
            ios ? l10n.autofillGuideIosEnable : l10n.autofillGuideAndroidEnable,
            if (!ios) l10n.autofillGuideChrome,
            l10n.autofillGuidePrepare,
            ios ? l10n.autofillGuideIosUse : l10n.autofillGuideAndroidUse,
            l10n.autofillGuideHelp,
          ];
          expect(
            tester.widget<AppBar>(find.byType(AppBar)).centerTitle,
            isFalse,
          );
          for (final text in instructions) {
            await tester.scrollUntilVisible(find.text(text), 150);
            expect(find.text(text), findsOneWidget);
            expect(tester.getSemantics(find.text(text)).label, contains(text));
            expect(tester.takeException(), isNull);
          }
          expect(
            find.text(
              ios ? l10n.autofillGuideAndroidUse : l10n.autofillGuideIosUse,
            ),
            findsNothing,
          );
          semantics.dispose();
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }
  }
}
