import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/widgets/auth_brand_header.dart';
import '../../../auth/data/services/hibp_service.dart';
import '../../../auth/presentation/cubit/password_security_cubit.dart';
import '../../../auth/presentation/widgets/password_security_status.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/password_strength.dart';
import '../cubit/onboarding_cubit.dart';
import '../widgets/onboarding_scaffold.dart';
import '../widgets/onboarding_text_field.dart';
import '../../../../core/widgets/primary_button.dart';

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
  late final PasswordSecurityCubit _passwordSecurity;

  @override
  void initState() {
    super.initState();
    _passwordSecurity = PasswordSecurityCubit(
      check: getIt<HibpService>().check,
    );
    AnalyticsService.instance.capture('onboarding', 'setup-page-viewed');

    // Pre-fill when navigating back — set text before attaching listeners
    // so the initial setState is not triggered unnecessarily.
    final saved = context.read<OnboardingCubit>().state.masterPassword;
    if (saved.isNotEmpty) {
      _passwordController.text = saved;
      _confirmController.text = saved;
      _passwordSecurity.checkPassword(saved);
    }

    _passwordController.addListener(_onPasswordChanged);
    _confirmController.addListener(_onTextChanged);
  }

  void _onPasswordChanged() {
    _passwordSecurity.checkPassword(_passwordController.text);
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _passwordSecurity.close();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PasswordSecurityCubit, PasswordSecurityState>(
      bloc: _passwordSecurity,
      builder: (context, securityState) =>
          _buildMasterPassword(context, securityState),
    );
  }

  Widget _buildMasterPassword(
    BuildContext context,
    PasswordSecurityState securityState,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    final strength = evaluatePasswordStrength(password);
    final passwordsMatch = password.isNotEmpty && password == confirm;
    final canSubmit =
        strength.isAcceptable &&
        passwordsMatch &&
        !securityState.blocksSubmission;

    return OnboardingScaffold(
      currentStep: 0,
      title: l10n.onboardingMasterPasswordTitle,
      subtitle: l10n.onboardingMasterPasswordSubtitle,
      titleFontSize: 18,
      centerContent: true,
      useAuthBrandLayout: true,
      header: const AuthBrandHeader(),
      footer: PrimaryButton(
        label: l10n.onboardingContinue,
        onPressed: canSubmit ? () => _submit(password) : null,
      ),
      children: [
        OnboardingTextField(
          label: l10n.onboardingMasterPasswordLabel,
          controller: _passwordController,
          obscureText: !_passwordVisible,
          suffixIcon: _visibilityButton(
            _passwordVisible,
            () => setState(() => _passwordVisible = !_passwordVisible),
          ),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
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
          suffixIcon: _visibilityButton(
            _confirmVisible,
            () => setState(() => _confirmVisible = !_confirmVisible),
          ),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        _RequirementsCard(l10n: l10n, password: password),
        const SizedBox(height: AppSpacing.fieldGap),
        PasswordSecurityStatusLine(
          password: password,
          isAcceptable: strength.isAcceptable,
          securityState: securityState,
          message: confirm.isNotEmpty && !passwordsMatch
              ? l10n.onboardingPasswordsDoNotMatch
              : null,
        ),
      ],
    );
  }

  Future<void> _submit(String password) async {
    await context.read<OnboardingCubit>().submitMasterPassword(password);
  }

  Widget _visibilityButton(bool visible, VoidCallback onToggle) {
    final brightness = Theme.of(context).brightness;
    return IconButton(
      icon: Icon(
        visible ? Icons.visibility_off : Icons.visibility,
        size: 20,
        color: AppColors.iconDefault(brightness),
      ),
      onPressed: onToggle,
    );
  }
}

class _RequirementsCard extends StatelessWidget {
  const _RequirementsCard({required this.l10n, required this.password});

  final AppLocalizations l10n;
  final String password;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasLength = password.length >= 12;
    final hasCase =
        RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[A-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final hasSymbol = RegExp(r'[^a-zA-Z0-9]').hasMatch(password);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.onboardingPasswordRequirementsTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface(brightness),
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          _requirement(l10n.onboardingPasswordReqLength, hasLength, brightness),
          _requirement(l10n.onboardingPasswordReqCase, hasCase, brightness),
          _requirement(l10n.onboardingPasswordReqNumber, hasNumber, brightness),
          _requirement(l10n.onboardingPasswordReqSymbol, hasSymbol, brightness),
        ],
      ),
    );
  }

  Widget _requirement(String label, bool met, Brightness brightness) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: met
                ? AppColors.positiveAccent
                : AppColors.onSurfaceSubtle(brightness),
          ),
          const SizedBox(width: AppSpacing.innerGap),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: met
                  ? AppColors.onSurface(brightness)
                  : AppColors.onSurfaceMuted(brightness),
            ),
          ),
        ],
      ),
    );
  }
}
