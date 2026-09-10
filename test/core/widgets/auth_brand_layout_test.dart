import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/core/widgets/auth_brand_layout.dart';

void main() {
  testWidgets('light mode mirrors the landing page background layers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: const Scaffold(
          body: AuthBrandBackground(child: SizedBox.expand()),
        ),
      ),
    );

    final gradients = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<Gradient>();

    expect(gradients.whereType<LinearGradient>(), isEmpty);
    final radialGradients = gradients.whereType<RadialGradient>().toList();
    expect(radialGradients, hasLength(2));

    final pageGradient = radialGradients.singleWhere(
      (gradient) => gradient.center == AppColors.authLightPageCenter,
    );
    expect(pageGradient.colors.first, AppColors.authLightPageStart);
    expect(
      pageGradient.colors[1],
      AppColors.authEntryLightPageGradient.colors[1],
    );
    expect(
      pageGradient.colors.last,
      AppColors.authEntryLightPageGradient.colors.last,
    );
    expect(pageGradient.stops, const [0, 0.46, 1]);

    final logoGlow = radialGradients.singleWhere(
      (gradient) => gradient.center == AppColors.authLightGlowCenter,
    );
    expect(logoGlow.stops, const [0, 0.14, 0.30, 0.44, 0.54, 0.68]);
    expect(logoGlow.colors.first.a, closeTo(0.98, 0.01));
    expect(logoGlow.colors.last.a, 0);

    final pageTransform = tester.widget<Transform>(
      find.byKey(const ValueKey('auth-light-page-gradient')),
    );
    expect(pageTransform.alignment, AppColors.authLightPageCenter);
    expect(pageTransform.transform.entry(0, 0), closeTo(2.5, 0.001));
    expect(pageTransform.transform.entry(1, 1), closeTo(844 * 2 / 390, 0.001));

    final glowTransform = tester.widget<Transform>(
      find.byKey(const ValueKey('auth-light-logo-glow')),
    );
    expect(glowTransform.alignment, AppColors.authLightGlowCenter);
    expect(glowTransform.transform.entry(0, 0), closeTo(1.38, 0.001));
    expect(
      glowTransform.transform.entry(1, 1),
      closeTo((844 * 2.2) / 390, 0.001),
    );
  });

  testWidgets('dark mode keeps the existing background treatment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: AuthBrandBackground(child: SizedBox.expand()),
        ),
      ),
    );

    final gradients = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<Gradient>();

    expect(gradients.whereType<LinearGradient>(), hasLength(1));
    final radialGradients = gradients.whereType<RadialGradient>().toList();
    expect(radialGradients, hasLength(1));
    expect(radialGradients.single.center, const Alignment(0, -0.2));
    expect(radialGradients.single.colors.first.a, closeTo(0.1, 0.01));
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
