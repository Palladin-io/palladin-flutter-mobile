import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Amber "Warning Zone" box — styled like the app's Danger Zone (rounded border + uppercase title)
/// but in the premium-amber tone. Shared so every security caveat (e.g. the `get` method exposing
/// plaintext, a `lifetime` grant that never expires) looks identical.
class WarningZone extends StatelessWidget {
  const WarningZone({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final amber = AppColors.premium(brightness);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amber.withValues(alpha: 0.3)),
        color: amber.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: amber,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          Text(
            message,
            style: TextStyle(color: AppColors.onSurfaceMuted(brightness), fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }
}
