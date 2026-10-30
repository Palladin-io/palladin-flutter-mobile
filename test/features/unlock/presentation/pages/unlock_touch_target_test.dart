import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/storage/biometric_key_store.dart';
import 'package:mobile_palladin/features/unlock/presentation/cubit/unlock_cubit.dart';
import 'package:mobile_palladin/features/unlock/presentation/pages/unlock_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Unlock extends MockCubit<UnlockState> implements UnlockCubit {}

void main() {
  setUpAll(
    () => registerFallbackValue(
      const BiometricPromptCopy(
        promptTitle: 'fixture',
        enrollTitle: 'fixture',
        accessTitle: 'fixture',
        cancelLabel: 'fixture',
      ),
    ),
  );
  for (final (locale, initialState) in [
    ('en', const UnlockInitial()),
    ('pl', const UnlockInitial()),
    ('en', const UnlockLoading()),
  ]) {
    testWidgets(
      'biometric touch target in $locale with ${initialState.runtimeType}',
      (tester) async {
        await getIt.reset();
        addTearDown(getIt.reset);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final cubit = _Unlock();
        whenListen(
          cubit,
          const Stream<UnlockState>.empty(),
          initialState: initialState,
        );
        when(() => cubit.isBiometricAvailable()).thenAnswer((_) async => true);
        when(
          () => cubit.unlockWithBiometrics(
            copy: any(named: 'copy'),
            defaultVaultName: any(named: 'defaultVaultName'),
          ),
        ).thenAnswer((_) async {});
        getIt.registerFactory<UnlockCubit>(() => cubit);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const UnlockPage(),
          ),
        );
        await tester.pump();
        final icon = find.byIcon(Icons.fingerprint);
        final center = tester.getCenter(icon);
        // 30px from centre lies beyond the old 48px button but inside the
        // enlarged target; the visible fingerprint keeps its original size.
        await tester.tapAt(center + const Offset(30, 0));
        await tester.pump();
        if (initialState is UnlockLoading) {
          verifyNever(
            () => cubit.unlockWithBiometrics(
              copy: any(named: 'copy'),
              defaultVaultName: any(named: 'defaultVaultName'),
            ),
          );
        } else {
          verify(
            () => cubit.unlockWithBiometrics(
              copy: any(named: 'copy'),
              defaultVaultName: any(named: 'defaultVaultName'),
            ),
          ).called(1);
        }
        final button = find.ancestor(
          of: icon,
          matching: find.byType(IconButton),
        );
        expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(72));
        final widget = tester.widget<IconButton>(button);
        expect(
          widget.tooltip,
          AppLocalizations.of(tester.element(icon))!.unlockBiometricHint,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
