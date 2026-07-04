import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Canonical two-line title for a pushed screen's [AppBar]: a 16/w700 name
/// with an optional 11px subtle subtitle below it. Use this instead of
/// hand-rolling the `Column(start, [Text, Text])` pattern.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle({super.key, required this.title, this.subtitle});

  final String title;

  /// Optional second line (status, vault name, …). When null or empty only
  /// the title renders.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final subtitle = this.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}
