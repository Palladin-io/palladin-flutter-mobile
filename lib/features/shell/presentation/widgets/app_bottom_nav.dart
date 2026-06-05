import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Persistent bottom navigation — five equal slots: Vaults, Agents, Home
/// (the app logo, slightly larger and poking above the bar), Approvals,
/// Settings. All labels share one baseline at the bottom; the bigger Home
/// logo extends upward into the small overhang above the bar.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.agentsBadgeCount = 0,
    this.approvalsBadgeCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Agents awaiting approval — shown as a badge on the Agents tab.
  final int agentsBadgeCount;

  /// Pending grant approvals — shown as a badge on the Approvals tab.
  final int approvalsBadgeCount;

  static const int tabVaults = 0;
  static const int tabAgents = 1;
  static const int tabHome = 2;
  static const int tabApprovals = 3;
  static const int tabSettings = 4;

  static const double _barHeight = 58;
  // Transparent headroom above the bar that the larger Home logo pokes into.
  static const double _overhang = 14;
  static const double _logoSize = 44; // grows upward only (labels stay aligned)

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return SizedBox(
      height: _overhang + _barHeight + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Bar background, anchored to the bottom.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: _barHeight + bottomInset,
              decoration: BoxDecoration(
                color: AppColors.navBackground(brightness),
                border: Border(
                  top: BorderSide(
                    color: AppColors.navBorder(brightness),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          // Items — span the full height (incl. overhang) so the Home logo can
          // extend above the bar, while every label stays bottom-aligned.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: bottomInset,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _NavItem(
                  label: l10n.navVaults,
                  icon: Icons.shield_outlined,
                  activeIcon: Icons.shield,
                  selected: currentIndex == tabVaults,
                  onTap: () => onTap(tabVaults),
                ),
                _NavItem(
                  label: l10n.navAgents,
                  icon: Icons.smart_toy_outlined,
                  activeIcon: Icons.smart_toy,
                  selected: currentIndex == tabAgents,
                  onTap: () => onTap(tabAgents),
                  badgeCount: agentsBadgeCount,
                ),
                _NavItem(
                  label: l10n.navHome,
                  iconWidget: Image.asset(
                    'assets/images/logo.png',
                    height: _logoSize,
                    width: _logoSize,
                    fit: BoxFit.contain,
                  ),
                  selected: currentIndex == tabHome,
                  onTap: () => onTap(tabHome),
                ),
                _NavItem(
                  label: l10n.navApprovals,
                  icon: Icons.verified_user_outlined,
                  activeIcon: Icons.verified_user,
                  selected: currentIndex == tabApprovals,
                  onTap: () => onTap(tabApprovals),
                  badgeCount: approvalsBadgeCount,
                ),
                _NavItem(
                  label: l10n.navSettings,
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  selected: currentIndex == tabSettings,
                  onTap: () => onTap(tabSettings),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single bottom-nav slot. Content is bottom-aligned so labels share one
/// baseline across slots regardless of icon size. Pass [icon]/[activeIcon]
/// (Material glyph) or a custom [iconWidget] (the Home logo).
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.activeIcon,
    this.iconWidget,
    this.badgeCount = 0,
  });

  final String label;
  final IconData? icon;
  final IconData? activeIcon;
  final Widget? iconWidget;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.brandRed : AppColors.textTertiary;
    Widget iconChild = iconWidget ??
        Icon(selected ? (activeIcon ?? icon) : icon, size: 24, color: color);
    if (badgeCount > 0) {
      iconChild = Badge.count(
        count: badgeCount,
        backgroundColor: AppColors.brandRed,
        textColor: AppColors.onBrandRed,
        child: iconChild,
      );
    }
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              iconChild,
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
