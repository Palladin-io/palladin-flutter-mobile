import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/data/services/hibp_service.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/password_security_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/widgets/password_security_status.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations_en.dart';

void main() {
  testWidgets('fades supporting copy into a breach warning and back', (
    tester,
  ) async {
    const supportingText = 'This password encrypts your vault locally.';
    final breachText = AppLocalizationsEn().authPasswordBreached;
    Widget app({bool breached = false}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PasswordSecurityStatusLine(
          password: breached ? 'test-only-password' : '',
          isAcceptable: breached,
          securityState: PasswordSecurityState(
            result: breached ? HibpResult.pwned : HibpResult.unknown,
          ),
          supportingText: supportingText,
        ),
      ),
    );

    await tester.pumpWidget(app());
    expect(find.text(supportingText), findsOneWidget);
    expect(find.text(breachText), findsNothing);

    await tester.pumpWidget(app(breached: true));
    await tester.pump(const Duration(milliseconds: 100));
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text(breachText),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(find.text(supportingText), findsNothing);
    expect(find.text(breachText), findsOneWidget);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text(supportingText), findsOneWidget);
    expect(find.text(breachText), findsNothing);
  });

  test('checks an eligible password and blocks while checking', () async {
    final cubit = PasswordSecurityCubit(
      debounce: Duration.zero,
      check: (_) async => HibpResult.notFound,
    );
    addTearDown(cubit.close);

    cubit.checkPassword('long-enough-password');
    expect(cubit.state.isChecking, isTrue);
    expect(cubit.state.blocksSubmission, isTrue);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.result, HibpResult.notFound);
    expect(cubit.state.isChecking, isFalse);
    expect(cubit.state.blocksSubmission, isFalse);
  });

  test(
    'ignores a stale breach-check result after the password changes',
    () async {
      final first = Completer<HibpResult>();
      final second = Completer<HibpResult>();
      var calls = 0;
      final cubit = PasswordSecurityCubit(
        debounce: Duration.zero,
        check: (_) => calls++ == 0 ? first.future : second.future,
      );
      addTearDown(cubit.close);

      cubit.checkPassword('first-long-password');
      await Future<void>.delayed(Duration.zero);
      cubit.checkPassword('second-long-password');
      await Future<void>.delayed(Duration.zero);

      first.complete(HibpResult.pwned);
      second.complete(HibpResult.notFound);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.result, HibpResult.notFound);
      expect(cubit.state.blocksSubmission, isFalse);
    },
  );

  testWidgets('renders the compact checking and secure states', (tester) async {
    final pending = Completer<HibpResult>();
    final cubit = PasswordSecurityCubit(
      debounce: Duration.zero,
      check: (_) => pending.future,
    );
    addTearDown(cubit.close);
    cubit.checkPassword('long-enough-password');

    await tester.pumpWidget(_testApp(cubit));
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
    final cubit = PasswordSecurityCubit(
      debounce: Duration.zero,
      check: (_) async => HibpResult.notFound,
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_testApp(cubit, message: 'Passwords do not match'));

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(find.text('Secure!'), findsNothing);
  });

  test(
    'a screen can replace Secure with its standard supporting copy',
    () async {
      final cubit = PasswordSecurityCubit(
        debounce: Duration.zero,
        check: (_) async => HibpResult.notFound,
      );
      addTearDown(cubit.close);

      cubit.checkPassword('long-enough-password');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final feedback = resolvePasswordSecurityFeedback(
        l10n: AppLocalizationsEn(),
        password: 'long-enough-password',
        isAcceptable: true,
        securityState: cubit.state,
        secureMessage: '',
      );

      expect(feedback.text, isEmpty);
    },
  );
}

Widget _testApp(PasswordSecurityCubit cubit, {String? message}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: BlocBuilder<PasswordSecurityCubit, PasswordSecurityState>(
        bloc: cubit,
        builder: (context, state) => PasswordSecurityStatusLine(
          password: 'long-enough-password',
          isAcceptable: true,
          securityState: state,
          message: message,
        ),
      ),
    ),
  );
}
