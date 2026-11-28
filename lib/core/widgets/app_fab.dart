import '../../features/shell/presentation/pages/app_shell.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared floating action button styled to match the mobile prototype's
/// `.fab` recipe — a 36px rounded square in [AppColors.primaryAction] with a
/// subtle white border and a brand-red drop shadow.
///
/// We bump the outer hit/visual size to 44×44 (Flutter's visual scale is
/// a touch tighter than the HTML prototype, and it brings the tap target
/// closer to Apple's 44pt minimum) while keeping the icon at 22px so the
/// glyph weight still reads.
///
/// Flutter's [FloatingActionButton] ships with a Material elevation
/// shadow that fights the brand-red glow we want, so we kill its
/// elevation entirely and paint the prototype's drop shadow ourselves
/// via a wrapping [DecoratedBox].
class AppFab extends StatelessWidget {
  // Match the shell Add FAB: 16dp scaffold margin + 8dp inset + 14dp
  // body extension behind the protruding navigation shield.
  static const double overlayBottom = 38;
  static const double extent = 44;

  static double scrollClearance(BuildContext context) =>
      overlayInset(context) + extent + AppSpacing.section;

  static double overlayInset(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppShellScope>() != null
      ? overlayBottom
      : AppSpacing.lg + MediaQuery.paddingOf(context).bottom;

  const AppFab({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.icon = Icons.add,
  }) : shellInset = false;

  const AppFab.shell({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.icon = Icons.add,
  }) : shellInset = true;

  final bool shellInset;
  final IconData icon;

  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: shellInset
          ? const EdgeInsets.only(
              right: AppSpacing.xs,
              bottom: AppSpacing.innerGap,
            )
          : EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            // Mirrors prototype `box-shadow: 0 3px 10px rgba(229,70,69,0.35)`
            // — `AppColors.fabShadow` is the brand-red tinted at 35% alpha,
            // kept as a const so this list can stay `const`-friendly.
            BoxShadow(
              color: AppColors.fabShadow,
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: SizedBox(
          width: extent,
          height: extent,
          child: FloatingActionButton(
            onPressed: onPressed,
            tooltip: tooltip,
            // Disable the implicit Hero animation Flutter wraps every FAB
            // in by default — the route transition would otherwise lift
            // the button (with its brand-red drop shadow) above the
            // outgoing page, leaving a shadow artifact on the element
            // sitting beneath the FAB on the destination route.
            heroTag: null,
            backgroundColor: AppColors.primaryAction,
            foregroundColor: AppColors.onBrandRed,
            elevation: 0,
            highlightElevation: 0,
            focusElevation: 0,
            hoverElevation: 0,
            disabledElevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.fabBorder, width: 1),
            ),
            child: Icon(icon, size: 22),
          ),
        ),
      ),
    );
  }
}
