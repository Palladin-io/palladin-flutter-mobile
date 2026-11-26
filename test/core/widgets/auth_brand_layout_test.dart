import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/core/widgets/auth_brand_layout.dart';
import 'package:mobile_palladin/core/widgets/brand_grain_surface.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('auth uses the approved canvas in $brightness', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(
            body: AuthBrandBackground(child: SizedBox.expand()),
          ),
        ),
      );

      expect(
        find.byType(BrandGrainOverlay),
        brightness == Brightness.dark ? findsOneWidget : findsNothing,
      );
      final background = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(AuthBrandBackground),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (background.decoration as BoxDecoration).gradient,
        AppColors.authGradient(brightness),
      );
    });
  }

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
