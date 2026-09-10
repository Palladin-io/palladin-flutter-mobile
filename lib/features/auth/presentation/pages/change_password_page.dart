import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/domain/password_strength.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/password_strength_bar.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/services/password_auth_crypto_service.dart';
import '../../domain/password_auth_exceptions.dart';
import '../bloc/auth_bloc.dart';
import '../cubit/change_password_cubit.dart';

/// Change-master-password screen.
///
/// Re-derives the auth hash + master key from the new password and
/// re-wraps the private key on-device; the recovery mnemonic is left
/// unchanged. On success the new master key is carried into the live
/// session via [VaultUnlocked] (the private key is unchanged) so vault
/// access continues uninterrupted.
class ChangePasswordPage extends StatelessWidget {
  const ChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChangePasswordCubit>(
      create: (_) => getIt<ChangePasswordCubit>(),
      child: const _ChangePasswordView(),
    );
  }
}

class _ChangePasswordView extends StatefulWidget {
  const _ChangePasswordView();

  @override
  State<_ChangePasswordView> createState() => _ChangePasswordViewState();
}

class _ChangePasswordViewState extends State<_ChangePasswordView> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _currentVisible = false;
  bool _newVisible = false;
  bool _confirmVisible = false;

  @override
  void initState() {
    super.initState();
    _currentController.addListener(_onChanged);
    _newController.addListener(_onChanged);
    _confirmController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocListener<ChangePasswordCubit, ChangePasswordState>(
      listener: _handleState,
      child: AppScreen.appBar(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          centerTitle: false,
          title: AppBarTitle(title: l10n.authChangePwTitle),
        ),
        body: BlocBuilder<ChangePasswordCubit, ChangePasswordState>(
          builder: (context, state) => _buildForm(context, l10n, state),
        ),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    AppLocalizations l10n,
    ChangePasswordState state,
  ) {
    final isLoading = state is ChangePasswordLoading;
    final wrongCurrent =
        state is ChangePasswordFailure &&
        state.error is ChangePasswordWrongCurrentException;
    final serverError =
        state is ChangePasswordFailure &&
        state.error is! ChangePasswordWrongCurrentException;

    final current = _currentController.text;
    final newPw = _newController.text;
    final confirm = _confirmController.text;
    final strength = evaluatePasswordStrength(newPw);
    final match = newPw.isNotEmpty && newPw == confirm;
    final differs = newPw.isNotEmpty && newPw != current;
    final canSubmit =
        !isLoading &&
        current.isNotEmpty &&
        strength.isAcceptable &&
        match &&
        differs;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.authChangePwSubtitle,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.onSurfaceSubtle(Theme.of(context).brightness),
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          OnboardingTextField(
            label: l10n.authChangePwCurrentLabel,
            controller: _currentController,
            obscureText: !_currentVisible,
            borderColor: wrongCurrent ? AppColors.brandRed : null,
            focusBorderColor: wrongCurrent ? AppColors.brandRed : null,
            feedbackVisible: wrongCurrent,
            feedbackReserveSpace: false,
            feedbackChild: Text(
              l10n.authChangePwWrongCurrent,
              style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
            ),
            suffixIcon: _toggle(
              _currentVisible,
              () => setState(() => _currentVisible = !_currentVisible),
            ),
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          OnboardingTextField(
            label: l10n.authChangePwNewLabel,
            controller: _newController,
            obscureText: !_newVisible,
            feedbackVisible: newPw.isNotEmpty,
            feedbackReserveSpace: false,
            feedbackChild: Text(
              differs
                  ? _strengthLabel(l10n, strength)
                  : l10n.authChangePwSameAsCurrent,
              style: TextStyle(
                fontSize: 12,
                color: differs ? _strengthColor(strength) : AppColors.brandRed,
                fontWeight: FontWeight.w500,
              ),
            ),
            suffixIcon: _toggle(
              _newVisible,
              () => setState(() => _newVisible = !_newVisible),
            ),
          ),
          SizedBox(
            height: AppSpacing.fieldGap,
            child: AnimatedOpacity(
              opacity: newPw.isNotEmpty ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: PasswordStrengthBar(strength: strength),
              ),
            ),
          ),
          OnboardingTextField(
            label: l10n.authChangePwConfirmLabel,
            controller: _confirmController,
            obscureText: !_confirmVisible,
            borderColor: (confirm.isNotEmpty && !match)
                ? AppColors.brandRed
                : null,
            focusBorderColor: (confirm.isNotEmpty && !match)
                ? AppColors.brandRed
                : null,
            feedbackVisible: confirm.isNotEmpty && !match,
            feedbackReserveSpace: false,
            feedbackChild: Text(
              l10n.onboardingPasswordsDoNotMatch,
              style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
            ),
            suffixIcon: _toggle(
              _confirmVisible,
              () => setState(() => _confirmVisible = !_confirmVisible),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          WarningZone(
            title: l10n.authChangePwWarningTitle,
            message: l10n.authChangePwWarning,
          ),
          if (serverError) ...[
            const SizedBox(height: AppSpacing.fieldGap),
            Text(
              _serverErrorMessage(l10n, (state).error),
              style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
            ),
          ],
          const SizedBox(height: AppSpacing.section),
          PrimaryButton(
            label: l10n.authChangePwButton,
            isLoading: isLoading,
            onPressed: canSubmit ? _submit : null,
          ),
        ],
      ),
    );
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final authState = context.read<AuthBloc>().state;
    final email = authState is AuthAuthenticated ? authState.email : null;
    if (email == null || email.isEmpty) {
      // No email on the session — cannot fetch the current auth salt. This
      // should never happen for a password account; surface a generic error.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.errorConnectionFailed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    context.read<ChangePasswordCubit>().changePassword(
      email: email,
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );
  }

  void _handleState(BuildContext context, ChangePasswordState state) {
    if (state is ChangePasswordSuccess) {
      // Refresh the live session's in-memory master key (private key is
      // unchanged) so future re-locks derive against the new ciphertext.
      context.read<AuthBloc>().add(
        VaultUnlocked(masterKey: state.masterKey, privateKey: state.privateKey),
      );
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.authChangePwSuccess),
            behavior: SnackBarBehavior.floating,
          ),
        );
      context.pop();
    }
  }

  Widget _toggle(bool visible, VoidCallback onToggle) {
    return IconButton(
      icon: Icon(
        visible ? Icons.visibility_off : Icons.visibility,
        size: 20,
        color: AppColors.iconMuted,
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

  Color _strengthColor(PasswordStrength strength) {
    return switch (strength) {
      PasswordStrength.tooShort || PasswordStrength.weak => AppColors.brandRed,
      PasswordStrength.fair => AppColors.strengthFair,
      PasswordStrength.strong ||
      PasswordStrength.veryStrong => AppColors.positiveAccent,
    };
  }

  String _serverErrorMessage(AppLocalizations l10n, Object error) {
    if (error is PasswordAuthServerException) {
      return switch (error.kind) {
        PasswordAuthServerErrorKind.serverNotResponding =>
          l10n.errorServerNotResponding,
        PasswordAuthServerErrorKind.cannotConnect =>
          l10n.errorCannotConnectToServer,
        PasswordAuthServerErrorKind.connectionFailed =>
          l10n.errorConnectionFailed,
        PasswordAuthServerErrorKind.invalidResponse =>
          l10n.errorInvalidServerResponse,
      };
    }
    return l10n.errorConnectionFailed;
  }
}
