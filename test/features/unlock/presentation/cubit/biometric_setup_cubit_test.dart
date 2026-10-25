import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_palladin/core/storage/biometric_key_store.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/unlock/presentation/cubit/biometric_setup_cubit.dart';

class Keys extends Mock implements BiometricKeyStore {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const copy = BiometricPromptCopy(
    promptTitle: 'dummy',
    enrollTitle: 'dummy',
    accessTitle: 'dummy',
    cancelLabel: 'dummy',
  );
  late Keys keys;
  late SharedPreferences prefs;
  late AuthState auth;
  late Uint8List sourceKey;
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(copy);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    keys = Keys();
    sourceKey = Uint8List.fromList(List.filled(32, 7));
    auth = AuthAuthenticated(
      userId: 'account-a',
      isOnboarded: true,
      isVaultLocked: false,
      masterKey: sourceKey,
      privateKey: Uint8List(32),
    );
    when(() => keys.generation).thenReturn(0);
    when(() => keys.canStore()).thenAnswer((_) async => true);
    when(() => keys.isEnrolled()).thenAnswer((_) async => false);
    when(() => keys.clear()).thenAnswer((_) async {});
    when(
      () => keys.enroll(
        any(),
        any(),
        expectedGeneration: any(named: 'expectedGeneration'),
      ),
    ).thenAnswer((_) async {});
  });
  BiometricSetupCubit build() => BiometricSetupCubit(
    keyStore: keys,
    preferences: prefs,
    currentAuth: () => auth,
  );

  test(
    'discovery never prompts; Not now persists only for this account',
    () async {
      final cubit = build();
      await cubit.refresh();
      expect(cubit.state.status, BiometricSetupStatus.available);
      verifyNever(
        () => keys.enroll(
          any(),
          any(),
          expectedGeneration: any(named: 'expectedGeneration'),
        ),
      );
      await cubit.dismiss();
      await cubit.close();
      final next = build();
      await next.refresh();
      expect(next.state.dismissed, isTrue);
      auth = const AuthAuthenticated(userId: 'account-b', isOnboarded: true);
      await next.refresh();
      expect(next.state.dismissed, isFalse);
      await next.close();
    },
  );

  test(
    'only Enable enrolls, then wipes its copy without changing live session keys',
    () async {
      Uint8List? supplied;
      when(() => keys.enroll(any(), any(), expectedGeneration: 0)).thenAnswer((
        call,
      ) async {
        supplied = call.positionalArguments[0] as Uint8List;
      });
      final cubit = build();
      await cubit.refresh();
      await cubit.enable(copy);
      expect(cubit.state.status, BiometricSetupStatus.enabled);
      expect(supplied, everyElement(0));
      expect(sourceKey, everyElement(7));
      expect(auth, isA<AuthAuthenticated>());
      await cubit.close();
    },
  );

  test(
    'declined biometric does not fail or clear the authenticated session',
    () async {
      when(() => keys.enroll(any(), any(), expectedGeneration: 0)).thenThrow(
        const BiometricAuthException(BiometricAuthFailureReason.canceled),
      );
      final cubit = build();
      await cubit.refresh();
      await cubit.enable(copy);
      expect(cubit.state.status, BiometricSetupStatus.available);
      expect(auth, isA<AuthAuthenticated>());
      expect(sourceKey, everyElement(7));
      await cubit.close();
    },
  );

  test(
    'closing during enrollment revokes its late copy and wipes its buffer',
    () async {
      final entered = Completer<void>();
      final finish = Completer<void>();
      Uint8List? supplied;
      when(() => keys.enroll(any(), any(), expectedGeneration: 0)).thenAnswer((
        call,
      ) async {
        supplied = call.positionalArguments[0] as Uint8List;
        entered.complete();
        await finish.future;
      });
      final cubit = build();
      await cubit.refresh();
      final enabling = cubit.enable(copy);
      await entered.future;
      await cubit.close();
      finish.complete();
      await enabling;
      verify(() => keys.clear()).called(1);
      expect(supplied, everyElement(0));
      expect(sourceKey, everyElement(7));
    },
  );
  test(
    'logout fences late enrollment without clearing a newer generation',
    () async {
      final entered = Completer<void>();
      final finish = Completer<void>();
      Uint8List? supplied;
      when(() => keys.enroll(any(), any(), expectedGeneration: 0)).thenAnswer((
        call,
      ) async {
        supplied = call.positionalArguments[0] as Uint8List;
        entered.complete();
        await finish.future;
      });
      final cubit = build();
      await cubit.refresh();
      final operation = cubit.enable(copy);
      await entered.future;
      auth = const AuthUnauthenticated();
      when(() => keys.generation).thenReturn(1);
      finish.complete();
      await operation;
      expect(cubit.state.status, isNot(BiometricSetupStatus.enabled));
      expect(supplied, everyElement(0));
      verifyNever(() => keys.clear());
      await cubit.close();
    },
  );

  test('failed protected deletion never reports disabled', () async {
    when(() => keys.isEnrolled()).thenAnswer((_) async => true);
    when(() => keys.clear()).thenThrow(const BiometricKeyCleanupException());
    final cubit = build();
    await cubit.refresh();
    await cubit.disable();
    expect(cubit.state.status, BiometricSetupStatus.enabled);
    expect(cubit.state.failed, isTrue);
    expect(auth, isA<AuthAuthenticated>());
    await cubit.close();
  });
}
