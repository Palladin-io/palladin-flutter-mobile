import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Canonical in-body header for every top-level list screen (Vaults,
/// Agents, Inbox …).
///
/// Rendered inside the scroll/content area — NOT a Material [AppBar] — so
/// the title sits a fixed [AppSpacing.headerGap] below the status bar and a
/// fixed [AppSpacing.headerGap] above the first control (search / segments),
/// identical on every screen. A Material AppBar would add its own toolbar
/// height and vertical centering, which made the title→content gap differ
/// from screen to screen — this widget is the single source that prevents
/// that drift.
class ListScreenHeader extends StatelessWidget {
  const ListScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });

  /// Screen title (e.g. "Vaults", "Agents", "Inbox").
  final String title;

  /// Optional one-line summary under the title (e.g. "2 agents · 2 active").
  final String? subtitle;

  /// Optional trailing actions aligned to the right of the title row.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.headerGap,
        AppSpacing.screenH,
        AppSpacing.headerGap,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (hasSubtitle) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}
