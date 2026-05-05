import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Generic "coming soon" placeholder used for tabs not yet implemented
/// (Agents, Audit, Settings).
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          title,
          style: TextStyle(color: AppColors.onSurface(brightness)),
        ),
        backgroundColor: AppColors.cardFill(brightness),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient(brightness),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: AppColors.onSurfaceSubtle(brightness)),
              const SizedBox(height: 12),
              Text(
                l10n.placeholderComingSoon,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.onSurfaceSubtle(brightness),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
