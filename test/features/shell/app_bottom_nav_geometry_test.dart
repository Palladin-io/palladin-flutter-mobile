import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/shell/presentation/widgets/app_bottom_nav.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  for (final inset in [0.0, 34.0]) {
    testWidgets('shield stays below body with $inset system inset', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = FakeViewPadding(bottom: inset);
      tester.view.viewPadding = FakeViewPadding(bottom: inset);
      addTearDown(tester.view.reset);
      const bodyKey = ValueKey('body');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: const SizedBox.expand(key: bodyKey),
            bottomNavigationBar: AppBottomNav(currentIndex: 0, onTap: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final nav = tester.getRect(find.byType(AppBottomNav));
      final separator = tester.getRect(find.byType(Divider));
      expect(separator.top, nav.top + 14);
      expect(nav.height, 72 + inset);
      final shield = tester.getRect(find.byType(Image));
      expect(shield.top, lessThan(separator.top));
      expect(shield.bottom, greaterThan(separator.bottom));
      expect(
        shield.top,
        greaterThanOrEqualTo(tester.getRect(find.byKey(bodyKey)).bottom),
      );
      expect(
        tester.getRect(find.text('Home')).bottom,
        lessThanOrEqualTo(844 - inset),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
