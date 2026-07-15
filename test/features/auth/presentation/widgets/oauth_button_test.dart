import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/core/theme/app_spacing.dart';
import 'package:mobile_palladin/features/auth/presentation/widgets/oauth_button.dart';
import 'package:mobile_palladin/features/auth/presentation/widgets/oauth_provider_icons.dart';

void main() {
  testWidgets('provider buttons use the app glass outline surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: OAuthButton(
            label: 'Continue with Apple',
            icon: const Icon(Icons.apple),
          ),
        ),
      ),
    );

    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{
        WidgetState.disabled,
      }),
      AppColors.cardFill(Brightness.dark),
    );
    expect(
      tester.getSize(find.byType(OAuthButton)).height,
      AppSpacing.controlHeight,
    );
  });

  testWidgets('provider icons render official artwork instead of text glyphs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            GoogleProviderIcon(),
            AppleProviderIcon(),
            XProviderIcon(),
          ],
        ),
      ),
    );

    expect(find.byType(Image), findsNWidgets(2));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('G'), findsNothing);
    expect(find.text('X'), findsNothing);
  });

  test('X artwork keeps semantic contrast in both themes', () {
    expect(
      XProviderIcon.colorFor(Brightness.light),
      AppColors.onSurface(Brightness.light),
    );
    expect(
      XProviderIcon.colorFor(Brightness.dark),
      AppColors.onSurface(Brightness.dark),
    );
  });

  testWidgets('every provider label uses the primary button typography', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            OAuthButton(
              label: 'Continue with Google',
              icon: GoogleProviderIcon(),
            ),
            OAuthButton(
              label: 'Continue with Apple',
              icon: AppleProviderIcon(),
            ),
            OAuthButton(label: 'Sign in with X', icon: XProviderIcon()),
          ],
        ),
      ),
    );

    for (final label in <String>[
      'Continue with Google',
      'Continue with Apple',
      'Sign in with X',
    ]) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.style?.fontSize, 13);
      expect(text.style?.fontWeight, FontWeight.w600);
      expect(text.style?.height, isNull);
    }
  });

  testWidgets('label stays on the button axis independently of the icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: OAuthButton(
                label: 'Continue with Google',
                icon: const GoogleProviderIcon(),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getCenter(find.text('Continue with Google')).dx,
      closeTo(tester.getCenter(find.byType(OAuthButton)).dx, 0.1),
    );
  });
}
