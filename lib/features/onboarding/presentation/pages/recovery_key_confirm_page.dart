import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';
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
  bool _confirmedFired = false;

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
    setState(() {});
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

        if (allCorrect && !_confirmedFired) {
          _confirmedFired = true;
          AnalyticsService.instance.capture('onboarding', 'recovery-key-confirmed');
        } else if (!allCorrect) {
          _confirmedFired = false;
        }

        return OnboardingScaffold(
          currentStep: 2,
          title: l10n.onboardingConfirmTitle,
          subtitle: l10n.onboardingConfirmSubtitle,
          onBack: () => context.read<OnboardingCubit>().goBack(),
          footer: PrimaryButton(
            label: l10n.onboardingConfirmVerify,
            isLoading: isSubmitting,
            onPressed: allCorrect && !isSubmitting
                ? () => context.read<OnboardingCubit>().completeSetup()
                : null,
          ),
          children: [
            for (var i = 0; i < _indices.length; i++) ...[
              _ConfirmationInput(
                wordIndex: _indices[i] + 1,
                controller: _controllers[i],
                result: results[i],
                l10n: l10n,
              ),
              const SizedBox(height: 16),
            ],
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
        ? AppColors.tealAccent
        : borderColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.onboardingConfirmWordLabel(wordIndex),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        OnboardingTextField(
          controller: controller,
          hintText: l10n.onboardingConfirmWordHint(wordIndex),
          borderColor: borderColor,
          focusBorderColor: focusBorderColor,
        ),
        // Always rendered (reserves space); animates in to prevent layout shift.
        AnimatedOpacity(
          opacity: result != _WordCheckResult.empty ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(
                  result == _WordCheckResult.correct
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 14,
                  color: result == _WordCheckResult.correct
                      ? AppColors.positiveAccent
                      : AppColors.brandRed,
                ),
                const SizedBox(width: 6),
                Text(
                  result == _WordCheckResult.correct
                      ? l10n.onboardingConfirmCorrect
                      : l10n.onboardingConfirmIncorrect,
                  style: TextStyle(
                    fontSize: 12,
                    color: result == _WordCheckResult.correct
                        ? AppColors.positiveAccent
                        : AppColors.brandRed,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
