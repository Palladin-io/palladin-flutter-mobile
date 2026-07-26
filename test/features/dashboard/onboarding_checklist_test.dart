import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/dashboard/domain/entities/onboarding_status.dart';
import 'package:mobile_palladin/features/dashboard/presentation/widgets/onboarding_checklist.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

const _status = OnboardingStatus(
  isOnboarded: false,
  entryCreated: false,
  apiKeyCreated: false,
  agentEnrolled: false,
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: SingleChildScrollView(
          child: OnboardingChecklist(
            status: _status,
            // Step 1 (notifications) done → step 2 (vault) is the active step.
            notificationStepDone: true,
            notificationPermissionDenied: false,
            onSkipSetup: _noop,
            onEnableNotifications: _noop,
            onSkipNotification: _noop,
            onVaultCta: _noop,
            onApiKeyCta: _noop,
            onAgentCta: _noop,
          ),
        ),
      ),
    ),
  );
}

void _noop() {}

void main() {
  group('OnboardingChecklist active-step CTA', () {
    testWidgets('renders the step-2 CTA as a compact, auto-width button', (
      tester,
    ) async {
      await _pump(tester);

      // The CTA label is present.
      expect(find.text('Go to Vaults'), findsOneWidget);

      // It is a filled ElevatedButton (the compact style), not a full-width
      // block: its width must be well under the available card width.
      final buttonSize = tester.getSize(
        find.ancestor(
          of: find.text('Go to Vaults'),
          matching: find.byType(ElevatedButton),
        ),
      );
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(buttonSize.width, lessThan(screenWidth / 2));
    });
  });
}
