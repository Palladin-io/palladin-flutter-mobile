import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/agents/presentation/pages/agent_detail_page.dart';
import '../../features/agents/presentation/pages/agents_page.dart';
import '../../features/api_keys/presentation/pages/api_key_detail_page.dart';
import '../../features/api_keys/presentation/pages/api_keys_page.dart';
import '../../features/audit/presentation/pages/global_audit_log_page.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/change_password_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/presentation/pages/totp_enroll_page.dart';
import '../../features/auth/presentation/pages/verify_email_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/notifications/presentation/pages/inbox_grants_page.dart';
import '../../features/notifications/presentation/pages/notification_center_page.dart';
import '../../features/notifications/presentation/pages/notification_preferences_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_wizard_page.dart';
import '../../features/recovery/presentation/pages/recovery_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/settings/presentation/pages/team_page.dart';
import '../../features/settings/presentation/pages/team_detail_pages.dart';
import '../../features/settings/presentation/pages/permissions_page.dart';
import '../../features/settings/presentation/pages/permission_role_page.dart';
import '../../features/settings/presentation/pages/security_page.dart';
import '../../features/settings/presentation/pages/data_import_page.dart';
import '../../features/settings/presentation/pages/billing_page.dart';
import '../../features/shell/presentation/pages/app_shell.dart';
import '../../features/unlock/presentation/pages/unlock_page.dart';
import '../../features/vault/presentation/pages/vault_detail_page.dart';
import '../../features/vault/presentation/pages/vault_list_page.dart';
import '../permissions.dart';
import 'shell_tab_page.dart';

/// Centralized route paths and builders, so widgets navigate via
/// `AppRoutes.agentDetail(id)` instead of scattering string literals
/// (CLAUDE.md routing criteria #6). Keep every path used by `context.go/push`
/// here next to its [GoRoute] definition below.
abstract final class AppRoutes {
  static const String settings = '/settings';
  static const String settingsGeneral = '/settings/general';
  static const String settingsTeam = '/settings/team';
  static const String settingsPermissions = '/settings/permissions';
  static const String settingsApiKeys = '/settings/api-keys';
  static const String settingsAudit = '/settings/audit';
  static const String settingsBilling = '/settings/billing';
  static const String settingsSecurity = '/settings/security';
  static const String settingsDataImport = '/settings/data-import';
  static const String changePassword = '/change-password';
  static const String totpEnroll = '/totp/enroll';

  static String settingsTeamMember(String userId) => '$settingsTeam/$userId';

  static String settingsTeamInvitation(String invitationId) =>
      '$settingsTeam/invitations/$invitationId';

  static String settingsPermissionRole(String roleId) =>
      '$settingsPermissions/$roleId';

  static String settingsApiKey(String keyId) => '$settingsApiKeys/$keyId';

  /// Agent detail screen for [agentId] (e.g. `/agents/abc`).
  static String agentDetail(String agentId) => '/agents/$agentId';

  /// Vault detail screen for [vaultId] (e.g. `/vaults/abc`).
  static String vaultDetail(String vaultId) => '/vaults/$vaultId';
}

/// Mirrors a settings affordance permission at the route boundary.
/// Backend authorization remains authoritative for every request.
String? settingsPermissionRedirect(
  AuthState authState,
  int requiredPermission, {
  String fallback = AppRoutes.settingsGeneral,
}) {
  if (authState is AuthAuthenticated &&
      (authState.permissions & requiredPermission) == 0) {
    return fallback;
  }
  return null;
}

CustomTransitionPage<void> _authFadePage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final duration = MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      );
    },
  );
}

ShellTabPage _shellTabPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => ShellTabPage(
  pageKey: state.pageKey,
  child: child,
  direction: state.extra is ShellTabDirection
      ? state.extra as ShellTabDirection
      : ShellTabDirection.none,
  disableAnimations: MediaQuery.disableAnimationsOf(context),
);

/// Creates the app-level [GoRouter] with auth-aware redirects.
///
/// Redirect rules, in order:
/// 1. Unauthenticated → `/login` (but `/register` and `/verify-email` are
///    allowed — registration, and the anonymous email-verification deep
///    link, must work without a session)
/// 2. Authenticated but not onboarded → `/onboarding`
/// 3. Authenticated, onboarded, email NOT verified → `/verify-email`
///    (the only route a verified-but-gated password account may sit on;
///    OAuth accounts are always verified so they never hit this)
/// 4. Authenticated, onboarded, verified, vault locked → `/unlock` (but
///    `/recovery` is allowed for locked sessions — that's its purpose)
/// 5. Fully set-up and unlocked user on an auth-only route → `/`
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
      final isOnRegisterPage = location == '/register';
      final isOnVerifyEmailPage = location == '/verify-email';
      final isVerificationDeepLink =
          isOnVerifyEmailPage &&
          (state.uri.queryParameters['token']?.isNotEmpty ?? false);
      final isOnOnboardingPage = location == '/onboarding';
      final isOnUnlockPage = location == '/unlock';
      final isOnRecoveryPage = location == '/recovery';

      final isAuthenticated = authState is AuthAuthenticated;

      // Keep the verification gate stable while logout cleanup is running.
      // Its terminal unauthenticated state will then redirect to login.
      if (authState is AuthLoading && isOnVerifyEmailPage) return null;

      if (!isAuthenticated) {
        // Registration and a verification deep link carrying a token are the
        // only routes reachable without a session. The token-less verify gate
        // belongs to an authenticated account, so logout returns to login.
        if (isOnLoginPage || isOnRegisterPage || isVerificationDeepLink) {
          return null;
        }
        return '/login';
      }

      final needsOnboarding = !authState.isOnboarded;
      if (needsOnboarding) {
        return isOnOnboardingPage ? null : '/onboarding';
      }

      // Email-verification gate — ahead of the vault. OAuth sessions are
      // always verified, so only unverified password accounts land here.
      if (!authState.emailVerified) {
        return isOnVerifyEmailPage ? null : '/verify-email';
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
          isOnRegisterPage ||
          isOnVerifyEmailPage ||
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
        pageBuilder: (context, state) =>
            _authFadePage(context, state, const LoginPage()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) =>
            _authFadePage(context, state, const RegisterPage()),
      ),
      GoRoute(
        // `?token=` present → verification-result mode (deep link); absent →
        // "please verify your email" gate with a resend action.
        path: '/verify-email',
        builder: (_, state) =>
            VerifyEmailPage(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const OnboardingWizardPage(),
      ),
      GoRoute(path: '/unlock', builder: (_, _) => const UnlockPage()),
      GoRoute(path: '/recovery', builder: (_, _) => const RecoveryPage()),
      GoRoute(
        // Master-password change — a focused full-screen flow
        // pushed from Settings; sits outside the shell so it has no bottom
        // nav. Guarded by the unlock redirect above (needs a session).
        path: '/change-password',
        builder: (_, _) => const ChangePasswordPage(),
      ),
      GoRoute(
        // TOTP enrollment — pushed from Settings › Security.
        path: '/totp/enroll',
        builder: (_, _) => const TotpEnrollPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // Home — landing tab. Dashboard with onboarding
          // checklist, unknown-agent prompt, or normal empty state. Lives
          // at `/` so the post-unlock redirect lands here directly.
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                _shellTabPage(context, state, const DashboardPage()),
          ),
          GoRoute(
            path: '/vaults',
            pageBuilder: (context, state) =>
                _shellTabPage(context, state, const VaultListPage()),
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
            pageBuilder: (context, state) =>
                _shellTabPage(context, state, const AgentsPage()),
            routes: [
              GoRoute(
                path: ':agentId',
                builder: (_, state) =>
                    AgentDetailPage(agentId: state.pathParameters['agentId']!),
              ),
            ],
          ),
          // Legacy Settings links remain valid while canonical destinations
          // live under /settings/*.
          GoRoute(path: '/audit', redirect: (_, _) => '/settings/audit'),
          // Keep older push/deep links working after Approvals became Inbox.
          GoRoute(path: '/approvals', redirect: (_, _) => '/inbox'),
          // Business Inbox — durable notifications for every authenticated
          // user. Grant actions reuse the existing zero-knowledge sheets.
          // `?focus=<id>` (from a tapped push) marks that item read on open.
          GoRoute(
            path: '/inbox',
            pageBuilder: (context, state) => _shellTabPage(
              context,
              state,
              NotificationCenterPage(
                focusId: state.uri.queryParameters['focus'],
              ),
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
          GoRoute(path: '/settings', redirect: (_, _) => '/settings/general'),
          GoRoute(
            path: '/settings/general',
            builder: (_, _) => const SettingsPage(),
          ),
          GoRoute(
            path: '/settings/team',
            builder: (_, _) => const TeamPage(),
            routes: [
              GoRoute(
                path: 'invitations/:invitationId',
                redirect: (context, state) {
                  return settingsPermissionRedirect(
                    authBloc.state,
                    Permissions.addUser,
                    fallback: AppRoutes.settingsTeam,
                  );
                },
                builder: (_, state) => TeamInvitationPage(
                  invitationId: state.pathParameters['invitationId']!,
                ),
              ),
              GoRoute(
                path: ':memberId',
                builder: (_, state) =>
                    TeamMemberPage(userId: state.pathParameters['memberId']!),
              ),
            ],
          ),
          GoRoute(
            path: '/settings/permissions',
            redirect: (context, state) {
              return settingsPermissionRedirect(
                authBloc.state,
                Permissions.organizationManagement,
              );
            },
            builder: (_, _) => const PermissionsPage(),
            routes: [
              GoRoute(
                path: ':roleId',
                redirect: (context, state) {
                  return settingsPermissionRedirect(
                    authBloc.state,
                    Permissions.organizationManagement,
                  );
                },
                builder: (_, state) =>
                    PermissionRolePage(roleId: state.pathParameters['roleId']!),
              ),
            ],
          ),
          // API keys — canonical Settings list + detail screens.
          GoRoute(
            path: '/settings/api-keys',
            redirect: (context, state) {
              return settingsPermissionRedirect(
                authBloc.state,
                Permissions.readApiKey,
              );
            },
            builder: (_, _) => const ApiKeysPage(),
            routes: [
              GoRoute(
                path: ':keyId',
                redirect: (context, state) {
                  return settingsPermissionRedirect(
                    authBloc.state,
                    Permissions.readApiKey,
                  );
                },
                builder: (_, state) =>
                    ApiKeyDetailPage(keyId: state.pathParameters['keyId']!),
              ),
            ],
          ),
          GoRoute(
            path: '/settings/audit',
            redirect: (context, state) {
              return settingsPermissionRedirect(
                authBloc.state,
                Permissions.auditView,
              );
            },
            builder: (_, _) => const GlobalAuditLogPage(),
          ),
          GoRoute(
            path: '/settings/billing',
            builder: (_, _) => const BillingPage(),
          ),
          GoRoute(
            path: '/settings/security',
            builder: (_, _) => const SecurityPage(),
          ),
          GoRoute(
            path: '/settings/data-import',
            builder: (_, _) => const DataImportPage(),
          ),
          GoRoute(path: '/api-keys', redirect: (_, _) => '/settings/api-keys'),
          GoRoute(
            path: '/api-keys/:keyId',
            redirect: (_, state) =>
                '/settings/api-keys/${state.pathParameters['keyId']!}',
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
