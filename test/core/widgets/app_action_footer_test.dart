import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_spacing.dart';
import 'package:mobile_palladin/core/widgets/app_action_footer.dart';

void main() {
  for (final scenario in [
    (inset: 0.0, outerSafeArea: false, keyboard: 0.0),
    (inset: 24.0, outerSafeArea: false, keyboard: 0.0),
    (inset: 48.0, outerSafeArea: false, keyboard: 0.0),
    (inset: 48.0, outerSafeArea: true, keyboard: 0.0),
    (inset: 48.0, outerSafeArea: false, keyboard: 300.0),
    (inset: 48.0, outerSafeArea: true, keyboard: 300.0),
  ]) {
    testWidgets(
      'footer keeps symmetric action spacing plus one system inset: $scenario',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.padding = FakeViewPadding(
          bottom: scenario.keyboard == 0 ? scenario.inset : 0,
        );
        tester.view.viewPadding = FakeViewPadding(bottom: scenario.inset);
        tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
        addTearDown(tester.view.reset);
        const action = SizedBox(key: ValueKey('action'), height: 44);
        const body = Column(
          children: [
            Spacer(),
            AppActionFooter(child: action),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: scenario.outerSafeArea ? const SafeArea(child: body) : body,
            ),
          ),
        );
        final actionRect = tester.getRect(find.byKey(const ValueKey('action')));
        final footerRect = tester.getRect(find.byType(AppActionFooter));
        final safeBottom =
            844 - (scenario.keyboard > 0 ? scenario.keyboard : scenario.inset);
        // The painted top border is separate from the content padding.
        expect(actionRect.top - footerRect.top - 1, AppSpacing.md);
        expect(safeBottom - actionRect.bottom, AppSpacing.md);
        expect(actionRect.left, AppSpacing.screenH);
        expect(actionRect.right, 390 - AppSpacing.screenH);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
