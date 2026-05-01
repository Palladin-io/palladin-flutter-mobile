import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_wizard_page.dart';
import '../../features/recovery/presentation/pages/recovery_page.dart';
import '../../features/unlock/presentation/pages/unlock_page.dart';
import '../../features/vault/presentation/pages/vault_detail_page.dart';
import '../../features/vault/presentation/pages/vault_list_page.dart';

/// Creates the app-level [GoRouter] with auth-aware redirects.
///
/// Redirect rules, in order:
/// 1. Unauthenticated → `/login`
/// 2. Authenticated but not onboarded → `/onboarding`
/// 3. Authenticated, onboarded, vault locked → `/unlock` (but `/recovery`
///    is allowed for locked sessions — that's the whole point of it)
/// 4. Fully set-up and unlocked user on `/login`, `/onboarding`,
///    `/unlock`, or `/recovery` → `/`
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
      final isOnRecoveryPage = location == '/recovery';

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
        // Recovery is the only flow available to a locked-but-authenticated
        // session besides unlock — the user needs it precisely because
        // they can't unlock.
        if (isOnUnlockPage || isOnRecoveryPage) return null;
        return '/unlock';
      }

      if (isOnLoginPage ||
          isOnOnboardingPage ||
          isOnUnlockPage ||
          isOnRecoveryPage) {
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
        path: '/recovery',
        builder: (_, _) => const RecoveryPage(),
      ),
      GoRoute(
        path: '/',
        builder: (_, _) => const VaultListPage(),
        routes: [
          GoRoute(
            path: 'vaults/:vaultId',
            builder: (_, state) => VaultDetailPage(
              vaultId: state.pathParameters['vaultId']!,
            ),
          ),
        ],
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
