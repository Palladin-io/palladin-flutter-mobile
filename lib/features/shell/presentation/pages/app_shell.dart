import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Top-level scaffold that wraps the four authenticated tabs
/// (Vaults, Agents, Audit, Settings) with a persistent
/// [BottomNavigationBar].
///
/// Used as the builder for the `ShellRoute` in `app_router.dart`.
/// Child routes decide their own background — the shell only owns
/// the chrome (the bottom nav).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _tabIndex(location);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) => _onTap(context, i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: AppColors.brandRed,
        unselectedItemColor: AppColors.textTertiary,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        elevation: 0,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.shield_outlined),
            activeIcon: const Icon(Icons.shield),
            label: l10n.navVaults,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.smart_toy_outlined),
            activeIcon: const Icon(Icons.smart_toy),
            label: l10n.navAgents,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.history),
            activeIcon: const Icon(Icons.history),
            label: l10n.navAudit,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }

  int _tabIndex(String location) {
    if (location.startsWith('/agents')) return 1;
    if (location.startsWith('/audit')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0; // vaults (default)
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/agents');
        break;
      case 2:
        context.go('/audit');
        break;
      case 3:
        context.go('/settings');
        break;
    }
  }
}
