import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Persistent bottom navigation bar shared by every authenticated
/// screen — both shell-hosted tabs (Home, Vaults, Agents, Audit,
/// Settings) and screens that live outside the [ShellRoute] but still
/// want to render the same chrome (e.g. the vault detail page).
///
/// Owns purely visual concerns — colors, item icons/labels and the
/// `top` border. Behaviour is delegated to the caller via [onTap], so
/// hosts that aren't in the shell can route by `context.go(...)` while
/// the shell can short-circuit the Settings index into opening its
/// end-drawer.
///
/// Tab indices are exposed as static constants so callers don't have to
/// memorize the order — use [AppBottomNav.tabVaults] etc. when wiring
/// `currentIndex` from outside the shell.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  /// Index of the currently selected tab. See the `tab*` constants for
  /// canonical values.
  final int currentIndex;

  /// Tap handler — receives the tapped tab index. Hosts should map the
  /// index to navigation (or, for Settings, to opening the drawer).
  final ValueChanged<int> onTap;

  static const int tabHome = 0;
  static const int tabVaults = 1;
  static const int tabAgents = 2;
  static const int tabAudit = 3;
  static const int tabSettings = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    // Owning the background + border on the wrapping [Container] (rather
    // than letting [BottomNavigationBar] paint its own background) is
    // what makes the 1-px top hairline actually visible. With the old
    // `DecoratedBox` setup the nav's solid background painted on top of
    // the border and clipped it away — moving the fill out and setting
    // the inner bar to transparent fixes that.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navBackground(brightness),
        border: Border(
          top: BorderSide(color: AppColors.navBorder(brightness), width: 1),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        selectedItemColor: AppColors.brandRed,
        unselectedItemColor: AppColors.textTertiary,
        selectedLabelStyle: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
        elevation: 0,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            activeIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
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
}
