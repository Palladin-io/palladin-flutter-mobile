import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/widgets/auth_brand_layout.dart';

void main() {
  testWidgets('uses the shared linear background and radial brand glow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AuthBrandBackground(child: SizedBox.expand())),
      ),
    );

    final gradients = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<Gradient>();

    expect(gradients.whereType<LinearGradient>(), hasLength(1));
    expect(gradients.whereType<RadialGradient>(), hasLength(1));
  });

  testWidgets('caps auth content at 320px after the minimum side gutters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: AuthContentWidth(
              child: ColoredBox(key: ValueKey('content'), color: Colors.red),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const ValueKey('content'))).width, 320);
  });
}
