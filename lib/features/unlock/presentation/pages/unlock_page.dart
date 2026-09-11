import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/storage/biometric_key_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/auth_brand_layout.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/widgets/auth_brand_header.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
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
    _passwordController.removeListener(_onTextChanged);
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
    final l10n = AppLocalizations.of(context)!;
    return BlocListener<UnlockCubit, UnlockState>(
      listener: _handleStateChange,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AuthBrandBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenH,
              ),
              child: AuthContentWidth(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AuthBrandHeader(caption: l10n.unlockTitle),
                                const SizedBox(
                                  height:
                                      AuthBrandHeader.labelledFormTopSpacing,
                                ),
                                _buildForm(context),
                              ],
                            ),
                            if (_biometricAvailable)
                              Center(child: _buildBiometricButton(context)),
                            Column(
                              children: [
                                _buildForgotPassword(context),
                                _buildLogout(context),
                                const SizedBox(height: AppSpacing.xxl),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<UnlockCubit, UnlockState>(
      builder: (context, state) {
        final isLoading = state is UnlockLoading;
        final hasError = state is UnlockFailed;
        final canSubmit = !isLoading && _passwordController.text.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnboardingTextField(
              label: l10n.unlockPasswordLabel,
              controller: _passwordController,
              obscureText: !_passwordVisible,
              textInputAction: TextInputAction.done,
              onSubmitted: canSubmit ? (_) => _submit() : null,
              borderColor: hasError ? AppColors.brandRed : null,
              focusBorderColor: hasError ? AppColors.brandRed : null,
              feedbackVisible: hasError,
              feedbackReserveSpace: false,
              feedbackChild: Text(
                hasError ? _resolveErrorMessage(context, state.error) : '',
                style: const TextStyle(fontSize: 12, color: AppColors.brandRed),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _passwordVisible ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: AppColors.iconMuted,
                ),
                onPressed: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            PrimaryButton(
              label: l10n.unlockButton,
              isLoading: isLoading,
              onPressed: canSubmit ? _submit : null,
            ),
          ],
        );
      },
    );
  }

  /// Text-less biometric shortcut — just the fingerprint affordance. The
  /// [AppLocalizations.unlockBiometricHint] string stays as the button tooltip
  /// (accessibility) even though no visible label is shown.
  Widget _buildBiometricButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<UnlockCubit, UnlockState>(
      builder: (context, state) {
        final isLoading = state is UnlockLoading;
        return IconButton(
          onPressed: isLoading ? null : _tryBiometrics,
          iconSize: 40,
          tooltip: l10n.unlockBiometricHint,
          icon: const Icon(
            Icons.fingerprint,
            color: AppColors.brandRed,
            size: 40,
          ),
        );
      },
    );
  }

  Widget _buildForgotPassword(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton(
      onPressed: () => context.go('/recovery'),
      child: Text(
        l10n.unlockForgotPassword,
        style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
      ),
    );
  }

  /// Escape hatch from a stale session — clears stored credentials and
  /// returns to the login screen (e.g. when the account no longer exists
  /// server-side and the master password can't unlock).
  Widget _buildLogout(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton(
      onPressed: () =>
          context.read<AuthBloc>().add(const AuthLogoutRequested()),
      child: Text(
        l10n.settingsLogout,
        style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
      ),
    );
  }

  /// Localized OS-prompt strings for the enclave-bound biometric store.
  /// Built here (where `AppLocalizations` is available) and threaded down —
  /// the data/core layer stays free of hardcoded user-facing text.
  BiometricPromptCopy _biometricCopy(AppLocalizations l10n) =>
      BiometricPromptCopy(
        promptTitle: l10n.unlockBiometricPromptTitle,
        enrollTitle: l10n.unlockBiometricEnrollPrompt,
        accessTitle: l10n.unlockBiometricPrompt,
        cancelLabel: l10n.vaultCancel,
      );

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final l10n = AppLocalizations.of(context)!;
    await context.read<UnlockCubit>().unlock(
      _passwordController.text,
      biometricCopy: _biometricCopy(l10n),
      defaultVaultName: l10n.defaultVaultName,
    );
  }

  Future<void> _tryBiometrics() async {
    FocusScope.of(context).unfocus();
    final l10n = AppLocalizations.of(context)!;
    await context.read<UnlockCubit>().unlockWithBiometrics(
      copy: _biometricCopy(l10n),
      defaultVaultName: l10n.defaultVaultName,
    );
  }

  void _handleStateChange(BuildContext context, UnlockState state) {
    if (state is UnlockSuccess) {
      if (state.viaBiometrics) {
        AnalyticsService.instance.capture('unlock', 'biometric-used');
      }
      // Analytics must fire before AuthBloc.add — the router disposes this
      // page as soon as the bloc transitions to unlocked state.
      AnalyticsService.instance.capture('unlock', 'vault-unlocked');
      context.read<AuthBloc>().add(
        VaultUnlocked(masterKey: state.masterKey, privateKey: state.privateKey),
      );
    } else if (state is UnlockFailed) {
      AnalyticsService.instance.capture(
        'unlock',
        'unlock-failed',
        properties: {'reason': _resolveFailureReason(state.error)},
      );
      if (state.error is SessionExpiredException) {
        // Session (refresh token) is dead — a valid session returns 200
        // regardless of password, so this can only be recovered by signing
        // in again. AuthBloc clears tokens and the router forwards to /login.
        context.read<AuthBloc>().add(const AuthLogoutRequested());
      }
    }
  }

  String _resolveFailureReason(Object error) {
    if (error is WrongMasterPasswordException) return 'wrong_password';
    if (error is SessionExpiredException) return 'session_expired';
    if (error is BiometricKeyMissingException) return 'biometric_missing';
    if (error is BiometricAuthFailedException) return 'biometric_failed';
    if (error is UnlockServerException) return 'server_error';
    return 'unknown';
  }

  String _resolveErrorMessage(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is WrongMasterPasswordException) {
      return l10n.unlockWrongPassword;
    }
    if (error is SessionExpiredException) {
      return l10n.unlockSessionExpired;
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
        UnlockServerErrorKind.cannotConnect => l10n.errorCannotConnectToServer,
        UnlockServerErrorKind.connectionFailed => l10n.errorConnectionFailed,
        UnlockServerErrorKind.invalidResponse =>
          l10n.errorInvalidServerResponse,
      };
    }
    return l10n.errorConnectionFailed;
  }
}
