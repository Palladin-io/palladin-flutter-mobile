import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../l10n/generated/app_localizations.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/oauth_button.dart';

/// Login screen with OAuth provider buttons.
///
/// Analytics events (deferred — PostHog not yet integrated):
///   - `mb:auth:login-page-viewed` on mount
///   - `mb:auth:oauth-clicked` on button tap (property: `provider`)
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: _handleStateChange,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.darkBackgroundGradient,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  _buildHero(context),
                  const Spacer(flex: 2),
                  _buildOAuthButtons(context),
                  const Spacer(flex: 1),
                  _buildFooter(context),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const subtitleStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      color: AppColors.textSecondary,
      height: 1.35,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/logo.png', height: 100),
        const SizedBox(height: 20),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Claw ',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  height: 1.0,
                  letterSpacing: -1.5,
                ),
              ),
              TextSpan(
                text: 'Vault',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  color: AppColors.brandRed,
                  height: 1.0,
                  letterSpacing: -1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.taglineZeroKnowledge, textAlign: TextAlign.center, style: subtitleStyle),
        Text(l10n.taglinePasswordManager, textAlign: TextAlign.center, style: subtitleStyle),
        Text(l10n.taglineForAiAgents, textAlign: TextAlign.center, style: subtitleStyle),
      ],
    );
  }

  Widget _buildOAuthButtons(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isLoading = state is AuthLoading;

        if (isLoading) {
          return const SizedBox(
            height: 180,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.tealAccent),
            ),
          );
        }

        final l10n = AppLocalizations.of(context)!;
        return Column(
          children: [
            OAuthButton(
              label: l10n.continueWithGoogle,
              icon: _googleIcon(),
              backgroundColor: AppColors.textPrimary,
              foregroundColor: Colors.black87,
              onPressed: () {
                // TODO: track mb:auth:oauth-clicked {provider: google}
                context.read<AuthBloc>().add(const AuthLoginWithGoogle());
              },
            ),
            const SizedBox(height: 12),
            OAuthButton(
              label: l10n.continueWithApple,
              icon: const Icon(Icons.apple, color: AppColors.textPrimary, size: 24),
              backgroundColor: AppColors.disabledButtonBackground,
              foregroundColor: AppColors.textPrimary,
              enabled: false,
              onDisabledTap: () => _showComingSoon(context, 'Apple'),
            ),
            const SizedBox(height: 12),
            OAuthButton(
              label: l10n.continueWithX,
              icon: _xIcon(),
              backgroundColor: AppColors.disabledButtonBackground,
              foregroundColor: AppColors.textPrimary,
              enabled: false,
              onDisabledTap: () => _showComingSoon(context, 'X'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        l10n.legalFooter,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  void _handleStateChange(BuildContext context, AuthState state) {
    if (state is AuthError) {
      final message = _resolveErrorMessage(context, state.error);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.brandRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  String _resolveErrorMessage(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is AuthServerException) {
      return switch (error.kind) {
        AuthServerErrorKind.serverNotResponding => l10n.errorServerNotResponding,
        AuthServerErrorKind.cannotConnect => l10n.errorCannotConnectToServer,
        AuthServerErrorKind.connectionFailed => l10n.errorConnectionFailed,
        AuthServerErrorKind.invalidResponse => l10n.errorInvalidServerResponse,
      };
    }
    return error.toString();
  }

  void _showComingSoon(BuildContext context, String provider) {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.providerComingSoon(provider)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Widget _googleIcon() {
    return const Center(
      child: Text(
        'G',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.googleBlue,
        ),
      ),
    );
  }

  Widget _xIcon() {
    return const Center(
      child: Text(
        'X',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
