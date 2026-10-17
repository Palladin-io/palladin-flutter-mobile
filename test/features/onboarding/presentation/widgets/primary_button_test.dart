import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_spacing.dart';
import 'package:mobile_palladin/core/widgets/primary_button.dart';

void main() {
  testWidgets('adaptive text height is preserved while loading', (
    tester,
  ) async {
    Future<void> pump(bool loading) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 134,
                child: PrimaryButton(
                  height: null,
                  label: 'Copy sharing link',
                  isLoading: loading,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await pump(false);
    final before = tester.getRect(find.byType(PrimaryButton));
    expect(before.height, greaterThan(AppSpacing.controlHeight));
    await pump(true);
    expect(tester.getRect(find.byType(PrimaryButton)), before);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports a leading icon while keeping its label centered', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: PrimaryButton(
                label: 'Continue with Email',
                leading: const Icon(Icons.mail_outline),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getCenter(find.text('Continue with Email')).dx,
      closeTo(tester.getCenter(find.byType(PrimaryButton)).dx, 0.1),
    );
    expect(
      tester.getSize(find.byType(PrimaryButton)).height,
      AppSpacing.controlHeight,
    );
  });
}
