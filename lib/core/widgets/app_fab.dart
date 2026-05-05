import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shared floating action button styled to match the mobile prototype's
/// `.fab` recipe — a 36px rounded square in [AppColors.brandRed] with a
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
  const AppFab({
    super.key,
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          // Mirrors prototype `box-shadow: 0 3px 10px rgba(255,79,79,0.35)`
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
        width: 44,
        height: 44,
        child: FloatingActionButton(
          onPressed: onPressed,
          tooltip: tooltip,
          // Disable the implicit Hero animation Flutter wraps every FAB
          // in by default — the route transition would otherwise lift
          // the button (with its brand-red drop shadow) above the
          // outgoing page, leaving a shadow artifact on the element
          // sitting beneath the FAB on the destination route.
          heroTag: null,
          backgroundColor: AppColors.brandRed,
          foregroundColor: AppColors.onBrandRed,
          elevation: 0,
          highlightElevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          disabledElevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(
              color: AppColors.fabBorder,
              width: 1,
            ),
          ),
          child: const Icon(Icons.add, size: 22),
        ),
      ),
    );
  }
}
