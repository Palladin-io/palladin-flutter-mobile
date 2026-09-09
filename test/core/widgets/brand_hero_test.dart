import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/core/theme/app_spacing.dart';
import 'package:mobile_palladin/core/widgets/brand_hero.dart';

void main() {
  testWidgets('uses the approved mobile brand lockup proportions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BrandHero(textColor: AppColors.onBrandRed)),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final gap = tester.widget<SizedBox>(
      find.descendant(
        of: find.byType(BrandHero),
        matching: find.byType(SizedBox),
      ),
    );
    final wordmark = tester.widget<RichText>(find.byType(RichText));
    final style = wordmark.text.style!;

    expect(image.height, 72);
    expect(gap.height, AppSpacing.xxl);
    expect(style.fontSize, 28);
    expect(style.fontWeight, FontWeight.w800);
    expect(style.letterSpacing, -0.28);
  });
}
