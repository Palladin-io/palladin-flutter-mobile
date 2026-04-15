import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../domain/unlock_exceptions.dart';
import '../cubit/unlock_cubit.dart';

/// Master Password Unlock Screen.
///
/// Displayed whenever an authenticated, onboarded user has a locked
/// vault — either right after login or after an explicit lock. Accepts
/// the master password and (when available) offers a biometric
/// shortcut that reads a previously-stashed master key from the OS
/// keychain/keystore.
///
/// Analytics:
///   - `mb:unlock:page-viewed`        on mount
///   - `mb:unlock:biometric-used`     after a successful biometric unlock
class UnlockPage extends StatelessWidget {
  const UnlockPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<UnlockCubit>(
      create: (_) => getIt<UnlockCubit>(),
      child: const _UnlockView(),
    );
  }
}

class _UnlockView extends StatefulWidget {
  const _UnlockView();

  @override
  State<_UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends State<_UnlockView> {
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.capture('unlock', 'page-viewed');
    _passwordController.addListener(_onTextChanged);
    _checkBiometricAvailability();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Re-render the "Unlock" button enabled/disabled state.
    setState(() {});
  }

  Future<void> _checkBiometricAvailability() async {
    final cubit = context.read<UnlockCubit>();
    final available = await cubit.isBiometricAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<UnlockCubit, UnlockState>(
      listener: _handleStateChange,
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 3),
                _buildHero(context),
                const Spacer(flex: 1),
                _buildForm(context),
                const Spacer(flex: 2),
                _buildForgotPassword(context),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/logo.png', height: 80),
        const SizedBox(height: 20),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Claw ',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  height: 1.0,
                  letterSpacing: -1.2,
                ),
              ),
              TextSpan(
                text: 'Vault',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: AppColors.brandRed,
                  height: 1.0,
                  letterSpacing: -1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.unlockTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textTertiary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<UnlockCubit, UnlockState>(
      builder: (context, state) {
        final isLoading = state is UnlockLoading;
        final hasError = state is UnlockFailed;
        final canSubmit =
            !isLoading && _passwordController.text.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PasswordField(
              label: l10n.unlockPasswordLabel,
              controller: _passwordController,
              visible: _passwordVisible,
              hasError: hasError,
              onToggleVisibility: () => setState(
                () => _passwordVisible = !_passwordVisible,
              ),
              onSubmitted: canSubmit ? (_) => _submit() : null,
            ),
            // Fixed-height row — always occupies the same space so the
            // button never jumps when an error appears or disappears.
            SizedBox(
              height: 24,
              child: hasError
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _resolveErrorMessage(context, state.error),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.brandRed,
                        ),
                      ),
                    )
                  : null,
            ),
            PrimaryButton(
              label: l10n.unlockButton,
              isLoading: isLoading,
              onPressed: canSubmit ? _submit : null,
            ),
            if (_biometricAvailable) ...[
              const SizedBox(height: 20),
              _buildBiometricRow(context, isLoading),
            ],
          ],
        );
      },
    );
  }

  Widget _buildBiometricRow(BuildContext context, bool isLoading) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        IconButton(
          onPressed: isLoading ? null : _tryBiometrics,
          iconSize: 40,
          tooltip: l10n.unlockBiometricHint,
          icon: const Icon(
            Icons.fingerprint,
            color: AppColors.tealAccent,
            size: 40,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.unlockBiometricHint,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPassword(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton(
      // TODO(CVT-27): wire recovery-key flow once the screen exists.
      onPressed: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(l10n.unlockForgotPasswordComingSoon),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
      },
      child: Text(
        l10n.unlockForgotPassword,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await context.read<UnlockCubit>().unlock(_passwordController.text);
  }

  Future<void> _tryBiometrics() async {
    FocusScope.of(context).unfocus();
    final l10n = AppLocalizations.of(context)!;
    await context.read<UnlockCubit>().unlockWithBiometrics(
          localizedReason: l10n.unlockBiometricPrompt,
        );
  }

  void _handleStateChange(BuildContext context, UnlockState state) {
    if (state is UnlockSuccess) {
      if (state.viaBiometrics) {
        // Fire analytics before the AuthBloc transition kicks the
        // router — the unlock page is disposed as soon as the redirect
        // takes effect.
        AnalyticsService.instance.capture('unlock', 'biometric-used');
      }
      context.read<AuthBloc>().add(VaultUnlocked(
            masterKey: state.masterKey,
            privateKey: state.privateKey,
          ));
    }
  }

  String _resolveErrorMessage(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is WrongMasterPasswordException) {
      return l10n.unlockWrongPassword;
    }
    if (error is BiometricKeyMissingException) {
      return l10n.unlockBiometricUnavailable;
    }
    if (error is BiometricAuthFailedException) {
      return l10n.unlockBiometricFailed;
    }
    if (error is UnlockServerException) {
      return switch (error.kind) {
        UnlockServerErrorKind.serverNotResponding =>
          l10n.errorServerNotResponding,
        UnlockServerErrorKind.cannotConnect =>
          l10n.errorCannotConnectToServer,
        UnlockServerErrorKind.connectionFailed => l10n.errorConnectionFailed,
        UnlockServerErrorKind.invalidResponse =>
          l10n.errorInvalidServerResponse,
      };
    }
    return l10n.errorConnectionFailed;
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.label,
    required this.controller,
    required this.visible,
    required this.hasError,
    required this.onToggleVisibility,
    required this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final bool visible;
  final bool hasError;
  final VoidCallback onToggleVisibility;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: !visible,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: onSubmitted,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.darkSurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: hasError
                  ? const BorderSide(color: AppColors.brandRed, width: 1)
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: hasError ? AppColors.brandRed : AppColors.tealAccent,
                width: 1.5,
              ),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                visible ? Icons.visibility_off : Icons.visibility,
                size: 20,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              onPressed: onToggleVisibility,
            ),
          ),
        ),
      ],
    );
  }
}
