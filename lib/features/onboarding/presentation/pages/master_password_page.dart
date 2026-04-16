import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/password_strength.dart';
import '../cubit/onboarding_cubit.dart';
import '../widgets/onboarding_scaffold.dart';
import '../widgets/onboarding_text_field.dart';
import '../widgets/password_strength_bar.dart';
import '../widgets/primary_button.dart';

/// Screen 1 of onboarding — master password entry + confirmation.
///
/// Submits the chosen password to the [OnboardingCubit], which generates
/// the recovery mnemonic and advances to the next step.
///
/// Fires `mb:onboarding:setup-page-viewed` on mount.
class MasterPasswordPage extends StatefulWidget {
  const MasterPasswordPage({super.key});

  @override
  State<MasterPasswordPage> createState() => _MasterPasswordPageState();
}

class _MasterPasswordPageState extends State<MasterPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _passwordVisible = false;
  bool _confirmVisible = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.capture('onboarding', 'setup-page-viewed');

    // Pre-fill when navigating back — set text before attaching listeners
    // so the initial setState is not triggered unnecessarily.
    final saved = context.read<OnboardingCubit>().state.masterPassword;
    if (saved.isNotEmpty) {
      _passwordController.text = saved;
      _confirmController.text = saved;
    }

    _passwordController.addListener(_onTextChanged);
    _confirmController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // Re-render strength bar and match indicator as the user types.
    setState(() {});
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    final strength = evaluatePasswordStrength(password);
    final passwordsMatch = password.isNotEmpty && password == confirm;
    final canSubmit = strength.isAcceptable && passwordsMatch;

    return OnboardingScaffold(
      currentStep: 0,
      title: l10n.onboardingMasterPasswordTitle,
      subtitle: l10n.onboardingMasterPasswordSubtitle,
      footer: PrimaryButton(
        label: l10n.onboardingContinue,
        onPressed: canSubmit ? () => _submit(password) : null,
      ),
      children: [
        OnboardingTextField(
          label: l10n.onboardingMasterPasswordLabel,
          controller: _passwordController,
          obscureText: !_passwordVisible,
          suffixIcon: _visibilityButton(_passwordVisible, () =>
              setState(() => _passwordVisible = !_passwordVisible)),
          feedbackVisible: password.isNotEmpty,
          feedbackChild: Text(
            _strengthLabel(l10n, strength),
            style: TextStyle(
              fontSize: 12,
              color: _strengthTextColor(strength),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        SizedBox(
          height: 12,
          child: AnimatedOpacity(
            opacity: password.isNotEmpty ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: PasswordStrengthBar(strength: strength),
            ),
          ),
        ),
        OnboardingTextField(
          label: l10n.onboardingConfirmPasswordLabel,
          controller: _confirmController,
          obscureText: !_confirmVisible,
          borderColor: (confirm.isNotEmpty && !passwordsMatch)
              ? AppColors.brandRed
              : null,
          focusBorderColor: (confirm.isNotEmpty && !passwordsMatch)
              ? AppColors.brandRed
              : null,
          feedbackVisible: confirm.isNotEmpty && !passwordsMatch,
          feedbackChild: Text(
            l10n.onboardingPasswordsDoNotMatch,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.brandRed,
            ),
          ),
          suffixIcon: _visibilityButton(_confirmVisible, () =>
              setState(() => _confirmVisible = !_confirmVisible)),
        ),
        const SizedBox(height: 12),
        _RequirementsCard(l10n: l10n, password: password),
      ],
    );
  }

  Future<void> _submit(String password) async {
    await context.read<OnboardingCubit>().submitMasterPassword(password);
  }

  Widget _visibilityButton(bool visible, VoidCallback onToggle) {
    return IconButton(
      icon: Icon(
        visible ? Icons.visibility_off : Icons.visibility,
        size: 20,
        color: Colors.white.withValues(alpha: 0.6),
      ),
      onPressed: onToggle,
    );
  }

  String _strengthLabel(AppLocalizations l10n, PasswordStrength strength) {
    return switch (strength) {
      PasswordStrength.tooShort => l10n.onboardingPasswordStrengthTooShort,
      PasswordStrength.weak => l10n.onboardingPasswordStrengthWeak,
      PasswordStrength.fair => l10n.onboardingPasswordStrengthFair,
      PasswordStrength.strong => l10n.onboardingPasswordStrengthStrong,
      PasswordStrength.veryStrong => l10n.onboardingPasswordStrengthVeryStrong,
    };
  }

  Color _strengthTextColor(PasswordStrength strength) {
    return switch (strength) {
      PasswordStrength.tooShort => AppColors.brandRed,
      PasswordStrength.weak => AppColors.brandRed,
      PasswordStrength.fair => AppColors.strengthFair,
      PasswordStrength.strong => AppColors.tealAccent,
      PasswordStrength.veryStrong => AppColors.tealAccent,
    };
  }
}


class _RequirementsCard extends StatelessWidget {
  const _RequirementsCard({required this.l10n, required this.password});

  final AppLocalizations l10n;
  final String password;

  @override
  Widget build(BuildContext context) {
    final hasLength = password.length >= 12;
    final hasCase = RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[A-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final hasSymbol = RegExp(r'[^a-zA-Z0-9]').hasMatch(password);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.onboardingPasswordRequirementsTitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          _requirement(l10n.onboardingPasswordReqLength, hasLength),
          _requirement(l10n.onboardingPasswordReqCase, hasCase),
          _requirement(l10n.onboardingPasswordReqNumber, hasNumber),
          _requirement(l10n.onboardingPasswordReqSymbol, hasSymbol),
        ],
      ),
    );
  }

  Widget _requirement(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: met
                ? AppColors.positiveAccent
                : Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: met ? Colors.white : Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
