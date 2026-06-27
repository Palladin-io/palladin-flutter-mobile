import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/agents/presentation/pages/agent_detail_page.dart';
import '../../features/agents/presentation/pages/agents_page.dart';
import '../../features/api_keys/presentation/pages/api_key_detail_page.dart';
import '../../features/api_keys/presentation/pages/api_keys_page.dart';
import '../../features/audit/presentation/pages/global_audit_log_page.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/notifications/presentation/pages/inbox_grants_page.dart';
import '../../features/notifications/presentation/pages/notification_center_page.dart';
import '../../features/notifications/presentation/pages/notification_preferences_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_wizard_page.dart';
import '../../features/recovery/presentation/pages/recovery_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/shell/presentation/pages/app_shell.dart';
import '../../features/shell/presentation/pages/placeholder_page.dart';
import '../../features/unlock/presentation/pages/unlock_page.dart';
import '../../features/vault/presentation/pages/vault_detail_page.dart';
import '../../features/vault/presentation/pages/vault_list_page.dart';
import '../../l10n/generated/app_localizations.dart';
import '../permissions.dart';

/// Centralized route paths and builders, so widgets navigate via
/// `AppRoutes.agentDetail(id)` instead of scattering string literals
/// (CLAUDE.md routing criteria #6). Keep every path used by `context.go/push`
/// here next to its [GoRoute] definition below.
abstract final class AppRoutes {
  /// Agent detail screen for [agentId] (e.g. `/agents/abc`).
  static String agentDetail(String agentId) => '/agents/$agentId';

  /// Vault detail screen for [vaultId] (e.g. `/vaults/abc`).
  static String vaultDetail(String vaultId) => '/vaults/$vaultId';
}

/// Creates the app-level [GoRouter] with auth-aware redirects.
///
/// Redirect rules, in order:
/// 1. Unauthenticated → `/login`
/// 2. Authenticated but not onboarded → `/onboarding`
/// 3. Authenticated, onboarded, vault locked → `/unlock` (but `/recovery`
///    is allowed for locked sessions — that's the whole point of it)
/// 4. Fully set-up and unlocked user on `/login`, `/onboarding`,
///    `/unlock`, or `/recovery` → `/`
GoRouter createRouter(
  AuthBloc authBloc, {
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
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
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const OnboardingWizardPage(),
      ),
      GoRoute(path: '/unlock', builder: (_, _) => const UnlockPage()),
      GoRoute(path: '/recovery', builder: (_, _) => const RecoveryPage()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // Home — landing tab. Currently a placeholder until CVT-32+
          // ships the real dashboard. Lives at `/` so the existing
          // post-unlock redirect lands here without further branching.
          GoRoute(
            path: '/',
            builder: (context, _) => PlaceholderPage(
              icon: Icons.home_outlined,
              title: AppLocalizations.of(context)!.navHome,
            ),
          ),
          GoRoute(
            path: '/vaults',
            builder: (_, _) => const VaultListPage(),
            routes: [
              // Nested under `/vaults` so the shell (and its persistent
              // bottom nav) stays mounted across navigation into the
              // detail page — otherwise the shell tears down and the
              // nav slides in/out on every push.
              GoRoute(
                path: ':vaultId',
                builder: (_, state) =>
                    VaultDetailPage(vaultId: state.pathParameters['vaultId']!),
              ),
            ],
          ),
          // Agents — standalone list + detail + edit screens. Nested so
          // the pushed detail / edit pages keep the shell (and its
          // bottom nav) mounted across navigation, matching
          // `/vaults/:vaultId`.
          GoRoute(
            path: '/agents',
            builder: (_, _) => const AgentsPage(),
            routes: [
              GoRoute(
                path: ':agentId',
                builder: (_, state) =>
                    AgentDetailPage(agentId: state.pathParameters['agentId']!),
              ),
            ],
          ),
          // Org-wide audit Logs screen (CVT-66) — reached from the settings
          // drawer's "Audit" item.
          GoRoute(
            path: '/audit',
            builder: (_, _) => const GlobalAuditLogPage(),
          ),
          // Keep older push/deep links working after Approvals became Inbox.
          GoRoute(path: '/approvals', redirect: (_, _) => '/inbox'),
          // Business Inbox — durable notifications for every authenticated
          // user. Grant actions reuse the existing zero-knowledge sheets.
          // `?focus=<id>` (from a tapped push) marks that item read on open.
          GoRoute(
            path: '/inbox',
            builder: (_, state) => NotificationCenterPage(
              focusId: state.uri.queryParameters['focus'],
            ),
            routes: [
              // Per-type × per-channel notification preferences. Pushed (not a
              // tab) so the back arrow returns to the inbox.
              GoRoute(
                path: 'preferences',
                builder: (_, _) => const NotificationPreferencesPage(),
              ),
              // Org-wide grants list (kebab → Grants). Pushed full-screen so
              // the back arrow returns to the inbox; the only mutable inbox
              // surface (live Revoke / re-grant).
              GoRoute(
                path: 'grants',
                builder: (_, _) => const InboxGrantsPage(),
              ),
            ],
          ),
          // Settings — organization details. Lives inside the shell so
          // the persistent bottom nav stays mounted while the user is
          // on the screen.
          GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
          // API keys — standalone list + detail screens. Nested so the
          // detail page keeps the shell (and its bottom nav) mounted
          // across navigation, matching `/vaults/:vaultId`.
          GoRoute(
            path: '/api-keys',
            redirect: (context, state) {
              final auth = authBloc.state;
              if (auth is AuthAuthenticated &&
                  (auth.permissions & Permissions.readApiKey) == 0) {
                return '/vaults';
              }
              return null;
            },
            builder: (_, _) => const ApiKeysPage(),
            routes: [
              GoRoute(
                path: ':keyId',
                redirect: (context, state) {
                  final auth = authBloc.state;
                  if (auth is AuthAuthenticated &&
                      (auth.permissions & Permissions.readApiKey) == 0) {
                    return '/vaults';
                  }
                  return null;
                },
                builder: (_, state) =>
                    ApiKeyDetailPage(keyId: state.pathParameters['keyId']!),
              ),
            ],
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
