import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_wizard_page.dart';
import '../../features/unlock/presentation/pages/unlock_page.dart';
import '../theme/app_colors.dart';

/// Temporary home page displayed after successful authentication.
///
/// Will be replaced by the real vault/dashboard feature shell.
class _PlaceholderHomePage extends StatelessWidget {
  const _PlaceholderHomePage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Text(l10n.appTitle),
        backgroundColor: AppColors.darkSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: l10n.unlockLockVault,
            onPressed: () {
              context.read<AuthBloc>().add(const VaultLockRequested());
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AuthBloc>().add(const AuthLogoutRequested());
            },
          ),
        ],
      ),
      body: Center(
        child: Text(
          l10n.welcomeMessage,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }
}

/// Creates the app-level [GoRouter] with auth-aware redirects.
///
/// Redirect rules, in order:
/// 1. Unauthenticated → `/login`
/// 2. Authenticated but not onboarded → `/onboarding`
/// 3. Authenticated, onboarded, vault locked → `/unlock`
/// 4. Fully set-up and unlocked user on `/login`, `/onboarding`, or
///    `/unlock` → `/`
GoRouter createRouter(AuthBloc authBloc) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _AuthBlocListenable(authBloc),
    redirect: (context, state) {
      final authState = authBloc.state;
      final location = state.matchedLocation;
      final isOnLoginPage = location == '/login';
      final isOnOnboardingPage = location == '/onboarding';
      final isOnUnlockPage = location == '/unlock';

      final isAuthenticated = authState is AuthAuthenticated;

      if (!isAuthenticated) {
        return isOnLoginPage ? null : '/login';
      }

      final needsOnboarding = !authState.isOnboarded;
      if (needsOnboarding) {
        return isOnOnboardingPage ? null : '/onboarding';
      }

      final isVaultLocked = authState.isVaultLocked;
      if (isVaultLocked) {
        return isOnUnlockPage ? null : '/unlock';
      }

      if (isOnLoginPage || isOnOnboardingPage || isOnUnlockPage) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, _) => const LoginPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const OnboardingWizardPage(),
      ),
      GoRoute(
        path: '/unlock',
        builder: (_, _) => const UnlockPage(),
      ),
      GoRoute(
        path: '/',
        builder: (_, _) => const _PlaceholderHomePage(),
      ),
    ],
  );
}

/// Bridges [AuthBloc] stream to [ChangeNotifier] so that [GoRouter]
/// can react to auth state changes and re-evaluate redirects.
class _AuthBlocListenable extends ChangeNotifier {
  _AuthBlocListenable(AuthBloc bloc) {
    _subscription = bloc.stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
