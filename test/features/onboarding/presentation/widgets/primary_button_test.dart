import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_spacing.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/primary_button.dart';

void main() {
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
