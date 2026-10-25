import 'dart:typed_data';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/storage/biometric_key_store.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/unlock/presentation/widgets/biometric_setup_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Keys extends Mock implements BiometricKeyStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AuthCheckRequested());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(
      const BiometricPromptCopy(
        promptTitle: 'dummy',
        enrollTitle: 'dummy',
        accessTitle: 'dummy',
        cancelLabel: 'dummy',
      ),
    );
  });
  testWidgets(
    'Home offers setup without prompting; cancel preserves the session and Not now hides it',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await getIt.reset();
      final keys = _Keys();
      final auth = _Auth();
      final session = AuthAuthenticated(
        userId: 'dummy',
        isOnboarded: true,
        isVaultLocked: false,
        masterKey: Uint8List(32),
      );
      when(() => auth.state).thenReturn(session);
      when(() => keys.generation).thenReturn(0);
      when(() => keys.isEnrolled()).thenAnswer((_) async => false);
      when(() => keys.canStore()).thenAnswer((_) async => true);
      when(() => keys.enroll(any(), any(), expectedGeneration: 0)).thenThrow(
        const BiometricAuthException(BiometricAuthFailureReason.canceled),
      );
      getIt.registerSingleton<BiometricKeyStore>(keys);
      await tester.pumpWidget(
        BlocProvider<AuthBloc>.value(
          value: auth,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: BiometricSetupCard(hideWhenHandled: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Enable biometric unlock'), findsOneWidget);
      verifyNever(() => keys.enroll(any(), any(), expectedGeneration: 0));
      await tester.tap(find.text('Enable biometric unlock'));
      await tester.pumpAndSettle();
      verify(() => keys.enroll(any(), any(), expectedGeneration: 0)).called(1);
      expect(auth.state, same(session));
      verifyNever(() => auth.add(any()));
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Enable biometric unlock'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await getIt.reset();
    },
  );
  for (final passwordChangeSucceeded in [true, false]) {
    testWidgets(
      'return after password change ($passwordChangeSucceeded) refreshes cleared enrollment',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await getIt.reset();
        final keys = _Keys();
        final auth = _Auth();
        var enrolled = true;
        when(() => auth.state).thenReturn(
          AuthAuthenticated(
            userId: 'dummy',
            isOnboarded: true,
            isVaultLocked: false,
            masterKey: Uint8List(32),
          ),
        );
        when(() => keys.isEnrolled()).thenAnswer((_) async => enrolled);
        when(() => keys.canStore()).thenAnswer((_) async => true);
        getIt.registerSingleton<BiometricKeyStore>(keys);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: auth,
            child: MaterialApp(
              navigatorKey: navigator,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: BiometricSetupCard()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Disable biometric unlock'), findsOneWidget);
        navigator.currentState!.push(
          MaterialPageRoute<bool>(
            builder: (_) => const Scaffold(body: Text('Password change')),
          ),
        );
        await tester.pumpAndSettle();
        // Production password change clears enrollment before the server request,
        // so both a successful request and a failed request invalidate this status.
        enrolled = false;
        navigator.currentState!.pop(passwordChangeSucceeded);
        await tester.pumpAndSettle();
        expect(find.text('Enable biometric unlock'), findsOneWidget);
        expect(find.text('Disable biometric unlock'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await getIt.reset();
      },
    );
  }
}
