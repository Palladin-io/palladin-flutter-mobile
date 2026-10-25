import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/widgets/app_action_footer.dart';

void main() {
  for (final scenario in [
    (inset: 24.0, outerSafeArea: false, keyboard: 0.0, buttonBottom: 812.0),
    (inset: 48.0, outerSafeArea: false, keyboard: 0.0, buttonBottom: 796.0),
    (inset: 48.0, outerSafeArea: true, keyboard: 0.0, buttonBottom: 764.0),
    (inset: 48.0, outerSafeArea: false, keyboard: 300.0, buttonBottom: 512.0),
  ]) {
    testWidgets('footer consumes only remaining insets: $scenario', (
      tester,
    ) async {
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
      expect(
        tester.getBottomRight(find.byKey(const ValueKey('action'))).dy,
        scenario.buttonBottom,
      );
    });
  }
}
