import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/mnemonic.dart';
import '../../domain/repositories/onboarding_repository.dart';
import '../cubit/onboarding_cubit.dart';
import '../widgets/onboarding_scaffold.dart';
import '../widgets/onboarding_text_field.dart';
import '../widgets/primary_button.dart';

/// Screen 3 of onboarding — verifies the user saved their recovery key
/// by asking them to type 3 specific words from the mnemonic.
///
/// On all 3 correct → fires `mb:onboarding:recovery-key-confirmed` and
/// runs the crypto pipeline via [OnboardingCubit.completeSetup].
class RecoveryKeyConfirmPage extends StatefulWidget {
  const RecoveryKeyConfirmPage({super.key});

  @override
  State<RecoveryKeyConfirmPage> createState() => _RecoveryKeyConfirmPageState();
}

class _RecoveryKeyConfirmPageState extends State<RecoveryKeyConfirmPage> {
  late final List<int> _indices;
  late final List<TextEditingController> _controllers;
  // Tracked outside of BlocBuilder.builder so analytics can be fired as
  // a side-effect from the BlocListener, keeping the builder pure.
  bool _allCorrect = false;

  @override
  void initState() {
    super.initState();
    final mnemonic = context.read<OnboardingCubit>().state.mnemonic;
    _indices = pickVerificationIndices(length: mnemonic.length);
    _controllers = List.generate(_indices.length, (_) => TextEditingController());
    for (final c in _controllers) {
      c.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    final mnemonic = context.read<OnboardingCubit>().state.mnemonic;
    final nowAllCorrect = _computeAllCorrect(mnemonic);
    if (nowAllCorrect != _allCorrect) {
      setState(() => _allCorrect = nowAllCorrect);
      if (nowAllCorrect) {
        // Side-effect fired from a user-input listener (not from a
        // BlocBuilder.builder), which makes it safe to run here.
        AnalyticsService.instance.capture('onboarding', 'recovery-key-confirmed');
      }
    } else {
      // Still need to rebuild so the per-field result icons update.
      setState(() {});
    }
  }

  bool _computeAllCorrect(List<String> mnemonic) {
    if (mnemonic.isEmpty) return false;
    for (var i = 0; i < _indices.length; i++) {
      final expected = mnemonic[_indices[i]].trim();
      final actual = _controllers[i].text.trim();
      if (actual.isEmpty) return false;
      if (actual.toLowerCase() != expected.toLowerCase()) return false;
    }
    return true;
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocConsumer<OnboardingCubit, OnboardingState>(
      listenWhen: (p, c) => p.error != c.error && c.error != null,
      listener: (context, state) {
        final error = state.error;
        if (error == null) return;
        final message = _resolveErrorMessage(l10n, error);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: AppColors.brandRed,
              behavior: SnackBarBehavior.floating,
            ),
          );
      },
      builder: (context, state) {
        final mnemonic = state.mnemonic;
        final isSubmitting = state.step == OnboardingStep.submitting;

        final results = List<_WordCheckResult>.generate(_indices.length, (i) {
          final expected = mnemonic[_indices[i]].trim();
          final actual = _controllers[i].text.trim();
          if (actual.isEmpty) {
            return _WordCheckResult.empty;
          }
          return actual.toLowerCase() == expected.toLowerCase()
              ? _WordCheckResult.correct
              : _WordCheckResult.incorrect;
        });

        final allCorrect =
            results.every((r) => r == _WordCheckResult.correct);

        // Button lives in the content flow right under the fields (web parity) —
        // not pinned to the screen bottom, which left a big empty gap for a
        // 3-field form. Empty feedback slots collapse so the fields stay tight.
        return OnboardingScaffold(
          currentStep: 2,
          title: l10n.onboardingConfirmTitle,
          subtitle: l10n.onboardingConfirmSubtitle,
          onBack: isSubmitting
              ? null
              : () => context.read<OnboardingCubit>().goBack(),
          children: [
            for (var i = 0; i < _indices.length; i++) ...[
              _ConfirmationInput(
                wordIndex: _indices[i] + 1,
                controller: _controllers[i],
                result: results[i],
                l10n: l10n,
              ),
              const SizedBox(height: AppSpacing.fieldGap),
            ],
            const SizedBox(height: AppSpacing.xs),
            PrimaryButton(
              label: l10n.onboardingConfirmVerify,
              isLoading: isSubmitting,
              onPressed: allCorrect && !isSubmitting
                  ? () => context.read<OnboardingCubit>().completeSetup(
                        defaultVaultName: l10n.defaultVaultName,
                      )
                  : null,
            ),
          ],
        );
      },
    );
  }

  String _resolveErrorMessage(AppLocalizations l10n, Object error) {
    if (error is OnboardingAlreadyCompletedException) {
      return l10n.onboardingAlreadyCompleted;
    }
    if (error is OnboardingServerException) {
      return switch (error.kind) {
        OnboardingServerErrorKind.serverNotResponding => l10n.errorServerNotResponding,
        OnboardingServerErrorKind.cannotConnect => l10n.errorCannotConnectToServer,
        OnboardingServerErrorKind.connectionFailed => l10n.errorConnectionFailed,
        OnboardingServerErrorKind.invalidResponse => l10n.errorInvalidServerResponse,
      };
    }
    return l10n.errorConnectionFailed;
  }
}

enum _WordCheckResult { empty, correct, incorrect }

class _ConfirmationInput extends StatelessWidget {
  const _ConfirmationInput({
    required this.wordIndex,
    required this.controller,
    required this.result,
    required this.l10n,
  });

  final int wordIndex;
  final TextEditingController controller;
  final _WordCheckResult result;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final borderColor = switch (result) {
      _WordCheckResult.empty => null,
      _WordCheckResult.correct => AppColors.positiveAccent,
      _WordCheckResult.incorrect => AppColors.brandRed,
    };

    final focusBorderColor = result == _WordCheckResult.empty
        ? AppColors.brandRed
        : borderColor;

    final isVisible = result != _WordCheckResult.empty;
    final isCorrect = result == _WordCheckResult.correct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnboardingTextField(
          label: l10n.onboardingConfirmWordLabel(wordIndex),
          controller: controller,
          hintText: l10n.onboardingConfirmWordHint(wordIndex),
          borderColor: borderColor,
          focusBorderColor: focusBorderColor,
        ),
        FieldFeedbackSlot(
          visible: isVisible,
          reserveSpace: false,
          child: Row(
            children: [
              Icon(
                isCorrect
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 14,
                color: isCorrect
                    ? AppColors.positiveAccent
                    : AppColors.brandRed,
              ),
              const SizedBox(width: AppSpacing.innerGap),
              Text(
                isCorrect
                    ? l10n.onboardingConfirmCorrect
                    : l10n.onboardingConfirmIncorrect,
                style: TextStyle(
                  fontSize: 12,
                  color: isCorrect
                      ? AppColors.positiveAccent
                      : AppColors.brandRed,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
