import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/data/services/hibp_service.dart';
import 'package:mobile_palladin/features/auth/presentation/widgets/password_security_status.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations_en.dart';

void main() {
  test('checks an eligible password and blocks while checking', () async {
    final controller = PasswordSecurityCheckController(
      debounce: Duration.zero,
      check: (_) async => HibpResult.notFound,
    );
    addTearDown(controller.dispose);

    controller.checkPassword('long-enough-password');
    expect(controller.isChecking, isTrue);
    expect(controller.blocksSubmission, isTrue);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.result, HibpResult.notFound);
    expect(controller.isChecking, isFalse);
    expect(controller.blocksSubmission, isFalse);
  });

  test(
    'ignores a stale breach-check result after the password changes',
    () async {
      final first = Completer<HibpResult>();
      final second = Completer<HibpResult>();
      var calls = 0;
      final controller = PasswordSecurityCheckController(
        debounce: Duration.zero,
        check: (_) => calls++ == 0 ? first.future : second.future,
      );
      addTearDown(controller.dispose);

      controller.checkPassword('first-long-password');
      await Future<void>.delayed(Duration.zero);
      controller.checkPassword('second-long-password');
      await Future<void>.delayed(Duration.zero);

      first.complete(HibpResult.pwned);
      second.complete(HibpResult.notFound);
      await Future<void>.delayed(Duration.zero);

      expect(controller.result, HibpResult.notFound);
      expect(controller.blocksSubmission, isFalse);
    },
  );

  testWidgets('renders the compact checking and secure states', (tester) async {
    final pending = Completer<HibpResult>();
    final controller = PasswordSecurityCheckController(
      debounce: Duration.zero,
      check: (_) => pending.future,
    );
    addTearDown(controller.dispose);
    controller.checkPassword('long-enough-password');

    await tester.pumpWidget(_testApp(controller));
    expect(find.text('Checking your password...'), findsOneWidget);
    final alignment = tester.widget<Align>(
      find.ancestor(
        of: find.text('Checking your password...'),
        matching: find.byType(Align),
      ),
    );
    expect(alignment.alignment, Alignment.center);

    pending.complete(HibpResult.notFound);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Secure!'), findsOneWidget);
  });

  testWidgets('a form error replaces the derived password status', (
    tester,
  ) async {
    final controller = PasswordSecurityCheckController(
      debounce: Duration.zero,
      check: (_) async => HibpResult.notFound,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _testApp(controller, message: 'Passwords do not match'),
    );

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(find.text('Secure!'), findsNothing);
  });

  test(
    'a screen can replace Secure with its standard supporting copy',
    () async {
      final controller = PasswordSecurityCheckController(
        debounce: Duration.zero,
        check: (_) async => HibpResult.notFound,
      );
      addTearDown(controller.dispose);

      controller.checkPassword('long-enough-password');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final feedback = resolvePasswordSecurityFeedback(
        l10n: AppLocalizationsEn(),
        password: 'long-enough-password',
        isAcceptable: true,
        controller: controller,
        secureMessage: '',
      );

      expect(feedback.text, isEmpty);
    },
  );
}

Widget _testApp(PasswordSecurityCheckController controller, {String? message}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: PasswordSecurityStatusLine(
        password: 'long-enough-password',
        isAcceptable: true,
        controller: controller,
        message: message,
      ),
    ),
  );
}
