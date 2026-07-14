import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_spacing.dart';
import 'package:mobile_palladin/core/widgets/brand_hero.dart';
import 'package:mobile_palladin/features/auth/presentation/widgets/auth_brand_header.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/onboarding_text_field.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('keeps the shared brand lockup geometry and copy', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(const AuthBrandHeader()));

    expect(find.byType(BrandHero), findsOneWidget);
    expect(find.text('Zero-knowledge by design.'), findsOneWidget);
    final padding = tester.widget<Padding>(
      find
          .ancestor(of: find.byType(BrandHero), matching: find.byType(Padding))
          .first,
    );
    expect(
      padding.padding,
      const EdgeInsets.only(top: AuthBrandHeader.defaultTopSpacing),
    );
    expect(
      AuthBrandHeader.labelledFormTopSpacing,
      AuthBrandHeader.formTopSpacing - AppSpacing.xxl,
    );
    expect(
      AuthBrandHeader.denseFormTopSpacing,
      lessThan(AuthBrandHeader.labelledFormTopSpacing),
    );
  });

  testWidgets('supports a persistent caption without changing the lockup', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(const AuthBrandHeader(caption: 'Enter your master password')),
    );

    expect(find.byType(BrandHero), findsOneWidget);
    expect(find.text('Enter your master password'), findsOneWidget);
    expect(find.text('Zero-knowledge by design.'), findsNothing);
  });

  testWidgets('aligns the email field border with the method picker CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const Column(
          children: [
            AuthBrandHeader(),
            SizedBox(height: AuthBrandHeader.formTopSpacing),
            SizedBox(key: Key('method-cta'), height: AppSpacing.controlHeight),
          ],
        ),
      ),
    );
    final methodTop = tester.getTopLeft(find.byKey(const Key('method-cta'))).dy;

    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _testApp(
        Column(
          children: [
            const AuthBrandHeader(),
            const SizedBox(height: AuthBrandHeader.labelledFormTopSpacing),
            OnboardingTextField(label: 'Email', controller: controller),
          ],
        ),
      ),
    );
    final fieldTop = tester.getTopLeft(find.byType(TextField)).dy;

    expect((fieldTop - methodTop).abs(), lessThanOrEqualTo(AppSpacing.xs));
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}
