import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';
import '../widgets/oauth_button.dart';

/// Login screen with OAuth provider buttons.
///
/// Matches the Claw Vault mobile prototype: dark background, centered
/// logo, tagline, three stacked OAuth buttons (Google enabled, Apple
/// and X disabled), and a legal footer.
///
/// Analytics events (deferred — PostHog not yet integrated):
///   - `mb:auth:login-page-viewed` on mount
///   - `mb:auth:oauth-clicked` on button tap (property: `provider`)
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  static const _bgColor = Color(0xFF000B2E);
  static const _brandRed = Color(0xFFFF4D5F);
  static const _tealAccent = Color(0xFF48ECDF);

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: _handleStateChange,
      child: Scaffold(
        backgroundColor: _bgColor,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 3),
                _buildLogo(),
                const SizedBox(height: 16),
                _buildTagline(context),
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
    );
  }

  Widget _buildLogo() {
    return RichText(
      textAlign: TextAlign.center,
      text: const TextSpan(
        children: [
          TextSpan(
            text: 'claw',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          TextSpan(
            text: 'vault',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              color: _brandRed,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagline(BuildContext context) {
    return Text(
      'Zero-Knowledge Password Manager\nfor AI Agents',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 14,
        color: Colors.white.withValues(alpha: 0.6),
        height: 1.4,
      ),
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
              child: CircularProgressIndicator(color: _tealAccent),
            ),
          );
        }

        return Column(
          children: [
            // Google — enabled
            OAuthButton(
              label: 'Continue with Google',
              icon: _googleIcon(),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              onPressed: () {
                // TODO: track mb:auth:oauth-clicked {provider: google}
                context.read<AuthBloc>().add(const AuthLoginWithGoogle());
              },
            ),
            const SizedBox(height: 12),
            // Apple — disabled (Phase 3)
            OAuthButton(
              label: 'Continue with Apple',
              icon: const Icon(Icons.apple, color: Colors.white, size: 24),
              backgroundColor: const Color(0xFF1a1a1a),
              foregroundColor: Colors.white,
              enabled: false,
              onDisabledTap: () => _showComingSoon(context, 'Apple'),
            ),
            const SizedBox(height: 12),
            // X — disabled (Phase 3)
            OAuthButton(
              label: 'Continue with X',
              icon: _xIcon(),
              backgroundColor: const Color(0xFF1a1a1a),
              foregroundColor: Colors.white,
              enabled: false,
              onDisabledTap: () => _showComingSoon(context, 'X'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        'By continuing, you agree to our Terms & Privacy Policy',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  void _handleStateChange(BuildContext context, AuthState state) {
    if (state is AuthError) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(state.message),
            backgroundColor: _brandRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    // Navigation is handled by go_router redirect — no manual push needed
  }

  void _showComingSoon(BuildContext context, String provider) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$provider sign-in coming soon'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// Google "G" icon rendered as a styled text glyph.
  /// In production this should use the official Google logo asset.
  Widget _googleIcon() {
    return const Center(
      child: Text(
        'G',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }

  /// X (formerly Twitter) logo rendered as a styled text glyph.
  Widget _xIcon() {
    return const Center(
      child: Text(
        'X',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
