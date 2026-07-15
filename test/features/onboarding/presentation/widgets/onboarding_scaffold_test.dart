import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/widgets/auth_brand_layout.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/onboarding_progress_dots.dart';

void main() {
  testWidgets('can vertically center form content', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnboardingScaffold(
          currentStep: 0,
          title: 'Create your account',
          subtitle: 'Enter your details',
          centerContent: true,
          children: [Text('form-content')],
        ),
      ),
    );

    final formColumn = tester.widget<Column>(
      find
          .ancestor(
            of: find.text('form-content'),
            matching: find.byType(Column),
          )
          .first,
    );

    expect(formColumn.mainAxisAlignment, MainAxisAlignment.center);
  });

  testWidgets('centered form remains scrollable on a short screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: OnboardingScaffold(
          currentStep: 0,
          title: 'Create your account',
          subtitle: 'Enter your details',
          centerContent: true,
          footer: SizedBox(height: 72),
          children: [SizedBox(height: 360)],
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports branded header and pinned legal footer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnboardingScaffold(
          currentStep: 0,
          title: 'Create your account',
          subtitle: 'Enter your details',
          centerContent: true,
          useAuthBrandLayout: true,
          header: Text('Palladin.io'),
          bottom: Text('Terms and Privacy Policy'),
          children: [Text('form-content')],
        ),
      ),
    );

    expect(find.text('Palladin.io'), findsOneWidget);
    expect(find.text('Terms and Privacy Policy'), findsOneWidget);
    expect(find.byType(OnboardingProgressDots), findsNothing);
    expect(find.byType(AuthBrandBackground), findsOneWidget);
  });

  testWidgets('supports a compact screen title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnboardingScaffold(
          currentStep: 0,
          title: 'Create your account',
          subtitle: 'Enter your details',
          titleFontSize: 20,
          children: [Text('form-content')],
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Create your account'));
    expect(title.style?.fontSize, 20);
  });

  testWidgets('supports a fixed form start below a branded header', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnboardingScaffold(
          currentStep: 0,
          title: '',
          subtitle: '',
          useAuthBrandLayout: true,
          header: SizedBox(key: Key('header'), height: 50),
          contentTopSpacing: 100,
          showTitleBlock: false,
          children: [Text('first-control')],
        ),
      ),
    );

    final headerBottom = tester.getBottomLeft(find.byKey(const Key('header')));
    final formTop = tester.getTopLeft(find.text('first-control'));
    expect(formTop.dy - headerBottom.dy, 100);
  });

  testWidgets('centers supporting copy without clipping the form footer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: OnboardingScaffold(
          currentStep: 0,
          title: '',
          subtitle: '',
          header: SizedBox(height: 120),
          contentTopSpacing: 24,
          showTitleBlock: false,
          centerFooterInRemainingSpace: true,
          footer: Text('supporting-copy'),
          bottom: Text('legal-copy'),
          children: [SizedBox(height: 360), Text('sign-in-prompt')],
        ),
      ),
    );

    final promptBottom = tester.getBottomLeft(find.text('sign-in-prompt')).dy;
    final supportCenter = tester.getCenter(find.text('supporting-copy')).dy;
    final legalTop = tester.getTopLeft(find.text('legal-copy')).dy;

    expect(find.text('sign-in-prompt'), findsOneWidget);
    expect(
      (supportCenter - promptBottom) - (legalTop - supportCenter),
      closeTo(0, 1),
    );
    expect(tester.takeException(), isNull);
  });
}
