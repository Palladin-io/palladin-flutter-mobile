import 'dart:async';
import 'package:dio/dio.dart';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/widgets/primary_button.dart';
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
    ('en', const UnlockLoading(viaBiometrics: true)),
    ('pl', const UnlockLoading(viaBiometrics: true)),
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
        await tester.pump();
        if (initialState is! UnlockLoading) {
          verify(
            () => cubit.unlockWithBiometrics(
              copy: any(named: 'copy'),
              defaultVaultName: any(named: 'defaultVaultName'),
            ),
          ).called(1);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          verifyNever(
            () => cubit.unlockWithBiometrics(
              copy: any(named: 'copy'),
              defaultVaultName: any(named: 'defaultVaultName'),
            ),
          );
        }
        final primary = tester.widget<PrimaryButton>(
          find.byType(PrimaryButton),
        );
        expect(
          primary.isLoading,
          initialState is UnlockLoading && !initialState.viaBiometrics,
        );
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
        expect(tester.getSize(button), const Size(72, 72));
        final biometricProgress = find.descendant(
          of: button,
          matching: find.byType(CircularProgressIndicator),
        );
        expect(
          biometricProgress,
          initialState is UnlockLoading && initialState.viaBiometrics
              ? findsOneWidget
              : findsNothing,
        );
        final widget = tester.widget<IconButton>(button);
        expect(
          widget.tooltip,
          AppLocalizations.of(tester.element(icon))!.unlockBiometricHint,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final scenario in ['unavailable', 'background', 'typing', 'disposed']) {
    testWidgets('automatic biometric waits safely: $scenario', (tester) async {
      await getIt.reset();
      addTearDown(getIt.reset);
      final cubit = _Unlock();
      final availability = Completer<bool>();
      whenListen(
        cubit,
        const Stream<UnlockState>.empty(),
        initialState: const UnlockInitial(),
      );
      when(
        () => cubit.isBiometricAvailable(),
      ).thenAnswer((_) => availability.future);
      when(
        () => cubit.unlockWithBiometrics(
          copy: any(named: 'copy'),
          defaultVaultName: any(named: 'defaultVaultName'),
        ),
      ).thenAnswer((_) async {});
      getIt.registerFactory<UnlockCubit>(() => cubit);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const UnlockPage(),
        ),
      );
      if (scenario == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else if (scenario == 'typing') {
        await tester.enterText(find.byType(TextField), 'synthetic');
        await tester.enterText(find.byType(TextField), '');
      } else if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox());
      }
      availability.complete(scenario != 'unavailable');
      await tester.pump();
      await tester.pump();
      verifyNever(
        () => cubit.unlockWithBiometrics(
          copy: any(named: 'copy'),
          defaultVaultName: any(named: 'defaultVaultName'),
        ),
      );
      if (scenario == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump();
        verify(
          () => cubit.unlockWithBiometrics(
            copy: any(named: 'copy'),
            defaultVaultName: any(named: 'defaultVaultName'),
          ),
        ).called(1);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final locale in ['en', 'pl']) {
    for (final network in [false, true]) {
      testWidgets(
        'unlock failure uses correct message network=$network in $locale',
        (tester) async {
          await getIt.reset();
          addTearDown(getIt.reset);
          final cubit = _Unlock();
          whenListen(
            cubit,
            const Stream<UnlockState>.empty(),
            initialState: UnlockFailed(
              network
                  ? DioException(
                      requestOptions: RequestOptions(path: '/fixture'),
                      type: DioExceptionType.connectionError,
                    )
                  : StateError('synthetic source changed'),
            ),
          );
          when(
            () => cubit.isBiometricAvailable(),
          ).thenAnswer((_) async => false);
          getIt.registerFactory<UnlockCubit>(() => cubit);
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const UnlockPage(),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(UnlockPage)),
          )!;
          expect(
            find.text(network ? l10n.errorConnectionFailed : l10n.unlockFailed),
            findsOneWidget,
          );
          expect(
            find.text(network ? l10n.unlockFailed : l10n.errorConnectionFailed),
            findsNothing,
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
