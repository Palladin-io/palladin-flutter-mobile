import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/l10n/locale_cubit.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_cubit.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../agents/presentation/bloc/agents_cubit.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

/// Bit on the JWT `permissions` claim that flags the user as a paying
/// (Pro) account. Mirrors `Permission.PremiumPlan = 256` on the backend
/// — kept private here so the only consumer (the drawer header badge)
/// has a single source of truth.
const int _kPremiumPlanBit = 256;

/// Sentinel value (`int.MaxValue` = `0x7FFFFFFF`) the backend hands out
/// to every user while the billing module is still being built. Without
/// this guard the `_kPremiumPlanBit` check is true for everyone and the
/// drawer header would advertise Pro for free-plan users. Drop this
/// constant and the `permissions != _kPermissionsMaxValue` clause once
/// the backend stops issuing the sentinel.
const int _kPermissionsMaxValue = 0x7FFFFFFF;

/// End-side drawer used by the vault list (and any other authenticated
/// surface that opts in) to expose the most common account actions
/// without dedicating a full bottom-nav tab to them.
///
/// Shows:
///   * a header with the user's avatar (initial), display name derived
///     from the email local-part, the email itself, and a Pro / Free
///     plan badge driven by the JWT `permissions` claim,
///   * a Dark mode toggle wired to [ThemeCubit] so users can flip
///     between dark and light at runtime,
///   * a Language selector (EN / PL) wired to [LocaleCubit] so users
///     can switch the UI locale at runtime,
///   * a Lock action that drops in-memory keys but keeps the user
///     signed in,
///   * a Logout action that fully signs out and returns to /login,
///   * an app-version footer for support diagnostics.
///
/// Pulls user metadata from [AuthBloc]'s [AuthAuthenticated] state and
/// the version string from [PackageInfo]. Falls back gracefully when
/// either is missing — never blocks the drawer from rendering.
class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final authState = context.watch<AuthBloc>().state;
    final email = authState is AuthAuthenticated ? authState.email : null;
    final permissions =
        authState is AuthAuthenticated ? authState.permissions : 0;
    final isPro = permissions != 0 &&
        permissions != _kPermissionsMaxValue &&
        (permissions & _kPremiumPlanBit) != 0;

    return Drawer(
      // Solid surface (`#181B22` in dark, `#F5F7FA` in light) so the
      // drawer reads as an opaque settings panel above the gradient
      // backdrop instead of bleeding through the nav's translucency.
      backgroundColor: AppColors.modalBackground(brightness),
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(email: email, isPro: isPro),
            Divider(color: AppColors.navBorder(brightness), height: 1),
            const SizedBox(height: AppSpacing.innerGap),
            const _ThemeToggleRow(),
            const _LanguageRow(),
            const SizedBox(height: AppSpacing.innerGap),
            Divider(color: AppColors.navBorder(brightness), height: 1),
            const SizedBox(height: AppSpacing.innerGap),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.innerGap,
                AppSpacing.screenH,
                AppSpacing.xs,
              ),
              child: Text(
                l10n.settingsAccountTitle.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textTertiaryMobile,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            _DrawerItem(
              icon: Icons.corporate_fare,
              label: l10n.settingsManageOrganization,
              onTap: () => _onNavigate(context, '/settings'),
            ),
            _DrawerItem(
              icon: Icons.vpn_key_outlined,
              label: l10n.settingsApiKeys,
              onTap: () => _onNavigate(context, '/api-keys'),
            ),
            _DrawerItem(
              icon: Icons.history,
              label: l10n.navAudit,
              onTap: () => _onNavigate(context, '/audit'),
            ),
            _DrawerItem(
              icon: Icons.lock_outline,
              label: l10n.settingsLockVault,
              onTap: () => _onLock(context),
            ),
            _DrawerItem(
              icon: Icons.logout,
              label: l10n.settingsLogout,
              onTap: () => _onLogout(context),
            ),
            const Spacer(),
            const _AppVersionFooter(),
          ],
        ),
      ),
    );
  }

  void _onNavigate(BuildContext context, String route) {
    // Close the drawer first so the destination screen lands on a clean
    // navigator stack — leaving the drawer open looks broken during the
    // route transition.
    Navigator.of(context).pop();
    context.push(route);
  }

  void _onLock(BuildContext context) {
    // Close the drawer first so the unlock screen lands on a clean
    // navigator stack — leaving it open looks broken during the
    // redirect.
    Navigator.of(context).pop();
    context.read<AuthBloc>().add(const VaultLockRequested());
  }

  void _onLogout(BuildContext context) {
    Navigator.of(context).pop();
    // Drop the previous session's agents from the singleton cubit so they
    // never leak into the next account that signs in on this device.
    getIt<AgentsCubit>().reset();
    context.read<AuthBloc>().add(const AuthLogoutRequested());
  }
}

/// Derives a human-readable display name from an email's local-part
/// (the bit before `@`). Splits on `.` and `_`, then title-cases each
/// chunk so `john.doe@x.com` becomes `John Doe`. Falls back to the
/// localised "User" label ([fallback]) when the email is missing or
/// empty — caller passes `l10n.settingsDefaultDisplayName` so the
/// fallback respects the active locale.
String _displayNameFor(String? email, String fallback) {
  if (email == null || email.isEmpty) return fallback;
  final local = email.split('@').first;
  if (local.isEmpty) return fallback;
  return local
      .split(RegExp(r'[._]'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.email, required this.isPro});

  final String? email;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final initial = _initialFor(email);
    final displayName = _displayNameFor(
      email,
      l10n.settingsDefaultDisplayName,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.xxl,
        AppSpacing.screenH,
        AppSpacing.xl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandRed.withValues(alpha: 0.18),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: AppColors.brandRed,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.onSurface(brightness),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.innerGap),
                    if (isPro)
                      _PlanBadgePro(label: l10n.settingsPlanPro)
                    else
                      _PlanBadgeFree(label: l10n.settingsPlanFree),
                  ],
                ),
                if (email != null && email!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textTertiaryMobile,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initialFor(String? email) {
    if (email == null || email.isEmpty) return '?';
    return email.characters.first.toUpperCase();
  }
}

/// Pro badge — amber `workspace_premium` glyph + label, low-alpha
/// amber pill so the affordance reads as a premium accent next to the
/// display name.
class _PlanBadgePro extends StatelessWidget {
  const _PlanBadgePro({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.innerGap,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.premiumAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.premiumAmber.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.workspace_premium,
            size: 12,
            color: AppColors.premiumAmber,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.premiumAmber,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Free-plan label — muted text, no chrome, sits inline with the
/// display name like a quiet meta tag.
class _PlanBadgeFree extends StatelessWidget {
  const _PlanBadgeFree({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textTertiaryMobile,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    );
  }
}

/// Dark / light theme switch row, wired to [ThemeCubit].
///
/// The switch is on whenever the cubit holds [ThemeMode.dark]. The app
/// still defaults to dark on cold start (see `flutter-mobile/CLAUDE.md`
/// — "Always ThemeMode.dark") but the user can flip to light from this
/// row.
class _ThemeToggleRow extends StatelessWidget {
  const _ThemeToggleRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final isDark = context.watch<ThemeCubit>().state == ThemeMode.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            // `brightness_6_outlined` reads as a generic theme toggle
            // — the previous moon-only `dark_mode_outlined` glyph
            // implied the row only had meaning when light mode was
            // off, which clashed with the now-functional switch.
            Icons.brightness_6_outlined,
            color: AppColors.iconDefault(brightness),
            size: 20,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              l10n.settingsThemeToggle,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Scaled-down stock [Switch] — the default size is too tall
          // for the drawer's compact 28-px row rhythm. The brand-red
          // active color and the white thumb anchor the toggle in the
          // app's accent system regardless of theme.
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: isDark,
              onChanged: (_) => context.read<ThemeCubit>().toggle(),
              // Thumb: text colour in off-state → clearly "off" not "disabled".
              // White in on-state → contrasts with the red track.
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.onBrandRed;
                }
                return AppColors.onSurface(brightness);
              }),
              // Track: transparent when off, subtle red tint when on.
              trackColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.brandRed.withValues(alpha: 0.3);
                }
                return Colors.transparent;
              }),
              // Outline makes the track visible when transparent.
              trackOutlineColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.transparent;
                }
                return AppColors.onSurface(brightness).withValues(alpha: 0.25);
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Language selector row — native [DropdownButton] wired to
/// [LocaleCubit].
///
/// Sits directly below the theme toggle and matches its compact
/// `horizontal: 20, vertical: 4` rhythm so the drawer's settings cluster
/// reads as a single visual block. We render full language names
/// ("English", "Polski") instead of EN / PL codes — a dropdown gives
/// us the headroom and the autonyms read as a more polished surface
/// than two-letter pills.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final current = context.watch<LocaleCubit>().state;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            Icons.language_outlined,
            color: AppColors.iconDefault(brightness),
            size: 20,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.settingsLanguage,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // ConstrainedBox keeps the popup menu within the drawer width —
          // without it the menu anchored at the far-right of the row can
          // exceed the screen's right edge on narrow devices.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: DropdownButton<Locale>(
            isExpanded: true,
            value: current,
            isDense: true,
            underline: const SizedBox.shrink(),
            // modalBackground gives near-white in light (#F5F7FA) and
            // solid navy in dark (#181B22) — better than the beige
            // cardSurface (#DCDEE2) which read as "wrong white".
            dropdownColor: AppColors.modalBackground(brightness),
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            iconEnabledColor: AppColors.textTertiaryMobile,
            // Compact flag + code shown in the closed button.
            selectedItemBuilder: (_) => [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🇬🇧', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'EN',
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🇵🇱', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'PL',
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            items: [
              DropdownMenuItem(
                value: const Locale('en'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🇬🇧', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: AppSpacing.innerGap),
                    Text(
                      'English',
                      style: TextStyle(color: AppColors.onSurface(brightness)),
                    ),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: const Locale('pl'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🇵🇱', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: AppSpacing.innerGap),
                    Text(
                      'Polski',
                      style: TextStyle(color: AppColors.onSurface(brightness)),
                    ),
                  ],
                ),
              ),
            ],
            onChanged: (locale) {
              if (locale != null) {
                context.read<LocaleCubit>().setLocale(locale);
              }
            },
          ),
          ),  // ConstrainedBox
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // Hand-rolled `InkWell` + `Padding` + `Row` instead of `ListTile`
    // so every drawer row aligns icons on the same x-axis (ListTile's
    // internal padding shifts by ±2-4 px depending on density and tile
    // height, which made the lock / logout glyphs look uneven against
    // the new theme-toggle row).
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenH,
          vertical: AppSpacing.cardPadding,
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.iconDefault(brightness), size: 20),
            const SizedBox(width: AppSpacing.lg),
            Text(
              label,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppVersionFooter extends StatelessWidget {
  const _AppVersionFooter();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        // While the platform call is in flight, render an invisible
        // placeholder of the same height so the drawer doesn't jump.
        final version = snapshot.data?.version ?? '';
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.innerGap,
            AppSpacing.screenH,
            AppSpacing.xl,
          ),
          child: Text(
            version.isEmpty ? '' : l10n.settingsAppVersion(version),
            style: const TextStyle(
              color: AppColors.textTertiaryMobile,
              fontSize: 11,
            ),
          ),
        );
      },
    );
  }
}
