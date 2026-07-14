import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/features/auth/presentation/widgets/rotating_welcome.dart';

void main() {
  testWidgets('matches the web welcome rotation timing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RotatingWelcome(
          messages: ['First message', 'Second message'],
          textColor: AppColors.onBrandRed,
        ),
      ),
    );

    expect(find.text('First message'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3800));
    final fading = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(fading.opacity, 0);

    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Second message'), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
  });

  testWidgets('does not rotate when animations are disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: RotatingWelcome(
            messages: ['First message', 'Second message'],
            textColor: AppColors.onBrandRed,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('First message'), findsOneWidget);
    expect(find.text('Second message'), findsNothing);
  });
}
