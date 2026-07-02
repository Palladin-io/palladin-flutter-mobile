import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/onboarding/domain/repositories/onboarding_repository.dart';
import 'package:mobile_palladin/features/onboarding/presentation/cubit/onboarding_cubit.dart';

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

void main() {
  late _MockOnboardingRepository mockRepo;

  final mnemonic = List<String>.generate(24, (i) => 'word${i + 1}');
  final unlockKeys = OnboardingUnlockKeys(
    masterKey: Uint8List.fromList(List.filled(32, 0xAA)),
    privateKey: Uint8List.fromList(List.filled(32, 0xBB)),
  );

  setUp(() {
    mockRepo = _MockOnboardingRepository();
  });

  group('OnboardingCubit', () {
    test('initial state is masterPassword step', () {
      final cubit = OnboardingCubit(repository: mockRepo);
      expect(cubit.state.step, OnboardingStep.masterPassword);
      expect(cubit.state.masterPassword, '');
      expect(cubit.state.mnemonic, isEmpty);
      cubit.close();
    });

    blocTest<OnboardingCubit, OnboardingState>(
      'submitMasterPassword stores password, generates mnemonic, advances to backup',
      build: () {
        when(() => mockRepo.generateRecoveryMnemonic())
            .thenAnswer((_) async => mnemonic);
        return OnboardingCubit(repository: mockRepo);
      },
      act: (cubit) => cubit.submitMasterPassword('Correct Horse Battery 9!'),
      expect: () => [
        predicate<OnboardingState>(
          (s) =>
              s.step == OnboardingStep.recoveryKeyBackup &&
              s.masterPassword == 'Correct Horse Battery 9!' &&
              s.mnemonic.length == 24,
        ),
      ],
      verify: (_) => verify(() => mockRepo.generateRecoveryMnemonic()).called(1),
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'acknowledgeRecoveryBackup moves from backup to confirm',
      build: () => OnboardingCubit(repository: mockRepo),
      seed: () => OnboardingState(
        step: OnboardingStep.recoveryKeyBackup,
        masterPassword: 'pw',
        mnemonic: mnemonic,
      ),
      act: (cubit) => cubit.acknowledgeRecoveryBackup(),
      expect: () => [
        predicate<OnboardingState>(
          (s) => s.step == OnboardingStep.recoveryKeyConfirm,
        ),
      ],
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'completeSetup emits submitting then completed with unlock keys on success',
      build: () {
        when(() => mockRepo.completeSetup(
              masterPassword: any(named: 'masterPassword'),
              recoveryMnemonic: any(named: 'recoveryMnemonic'),
              defaultVaultName: any(named: 'defaultVaultName'),
            )).thenAnswer((_) async => unlockKeys);
        return OnboardingCubit(repository: mockRepo);
      },
      seed: () => OnboardingState(
        step: OnboardingStep.recoveryKeyConfirm,
        masterPassword: 'Correct Horse Battery 9!',
        mnemonic: mnemonic,
      ),
      act: (cubit) => cubit.completeSetup(defaultVaultName: 'Personal'),
      expect: () => [
        predicate<OnboardingState>((s) => s.step == OnboardingStep.submitting),
        predicate<OnboardingState>(
          (s) =>
              s.step == OnboardingStep.completed && s.unlockKeys == unlockKeys,
        ),
      ],
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'clearUnlockKeys drops the reference without touching later steps',
      build: () => OnboardingCubit(repository: mockRepo),
      seed: () => OnboardingState(
        step: OnboardingStep.completed,
        masterPassword: 'pw',
        mnemonic: mnemonic,
        unlockKeys: unlockKeys,
      ),
      act: (cubit) => cubit.clearUnlockKeys(),
      expect: () => [
        predicate<OnboardingState>(
          (s) => s.step == OnboardingStep.completed && s.unlockKeys == null,
        ),
      ],
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'completeSetup treats OnboardingAlreadyCompletedException as success',
      build: () {
        when(() => mockRepo.completeSetup(
              masterPassword: any(named: 'masterPassword'),
              recoveryMnemonic: any(named: 'recoveryMnemonic'),
              defaultVaultName: any(named: 'defaultVaultName'),
            )).thenThrow(OnboardingAlreadyCompletedException());
        return OnboardingCubit(repository: mockRepo);
      },
      seed: () => OnboardingState(
        step: OnboardingStep.recoveryKeyConfirm,
        masterPassword: 'pw',
        mnemonic: mnemonic,
      ),
      act: (cubit) => cubit.completeSetup(defaultVaultName: 'Personal'),
      expect: () => [
        predicate<OnboardingState>((s) => s.step == OnboardingStep.submitting),
        predicate<OnboardingState>(
          (s) =>
              s.step == OnboardingStep.completed &&
              s.error == null &&
              s.unlockKeys == null,
        ),
      ],
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'completeSetup surfaces error and returns to confirm step on failure',
      build: () {
        when(() => mockRepo.completeSetup(
              masterPassword: any(named: 'masterPassword'),
              recoveryMnemonic: any(named: 'recoveryMnemonic'),
              defaultVaultName: any(named: 'defaultVaultName'),
            )).thenThrow(const OnboardingServerException(
          OnboardingServerErrorKind.cannotConnect,
        ));
        return OnboardingCubit(repository: mockRepo);
      },
      seed: () => OnboardingState(
        step: OnboardingStep.recoveryKeyConfirm,
        masterPassword: 'pw',
        mnemonic: mnemonic,
      ),
      act: (cubit) => cubit.completeSetup(defaultVaultName: 'Personal'),
      expect: () => [
        predicate<OnboardingState>((s) => s.step == OnboardingStep.submitting),
        predicate<OnboardingState>(
          (s) =>
              s.step == OnboardingStep.recoveryKeyConfirm &&
              s.error is OnboardingServerException,
        ),
      ],
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'completeSetup is a no-op when state is missing password/mnemonic',
      build: () => OnboardingCubit(repository: mockRepo),
      act: (cubit) => cubit.completeSetup(defaultVaultName: 'Personal'),
      expect: () => const <OnboardingState>[],
      verify: (_) => verifyNever(() => mockRepo.completeSetup(
            masterPassword: any(named: 'masterPassword'),
            recoveryMnemonic: any(named: 'recoveryMnemonic'),
            defaultVaultName: any(named: 'defaultVaultName'),
          )),
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'goBack steps back from confirm to backup, then to master password',
      build: () => OnboardingCubit(repository: mockRepo),
      seed: () => OnboardingState(
        step: OnboardingStep.recoveryKeyConfirm,
        masterPassword: 'pw',
        mnemonic: mnemonic,
      ),
      act: (cubit) => cubit
        ..goBack()
        ..goBack(),
      expect: () => [
        predicate<OnboardingState>(
          (s) => s.step == OnboardingStep.recoveryKeyBackup,
        ),
        predicate<OnboardingState>(
          (s) => s.step == OnboardingStep.masterPassword,
        ),
      ],
    );
  });
}
