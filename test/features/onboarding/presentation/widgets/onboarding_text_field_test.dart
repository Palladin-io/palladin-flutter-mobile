import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_spacing.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/onboarding_text_field.dart';

void main() {
  testWidgets('suffix button does not increase the input height', (
    tester,
  ) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    addTearDown(emailController.dispose);
    addTearDown(passwordController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              OnboardingTextField(controller: emailController),
              OnboardingTextField(
                controller: passwordController,
                obscureText: true,
                suffixIcon: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.visibility),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final fields = find.byType(TextField);
    final emailHeight = tester.getSize(fields.at(0)).height;
    final passwordHeight = tester.getSize(fields.at(1)).height;

    expect(emailHeight, AppSpacing.controlHeight);
    expect(passwordHeight, emailHeight);
  });
}
