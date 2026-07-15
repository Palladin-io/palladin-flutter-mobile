import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Shared separator between password authentication and OAuth providers.
class AuthProviderDivider extends StatelessWidget {
  const AuthProviderDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final color = AppColors.cardBorder(brightness);

    return Row(
      children: [
        Expanded(child: Divider(height: 1, thickness: 1, color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            l10n.authOrDivider,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
          ),
        ),
        Expanded(child: Divider(height: 1, thickness: 1, color: color)),
      ],
    );
  }
}
