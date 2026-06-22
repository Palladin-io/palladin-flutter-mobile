import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../settings/domain/entities/api_key.dart';

/// Status pill for an API key — teal for active, red for revoked.
///
/// Shared by the API-keys list card and the detail screen so both
/// surfaces render the same affordance.
class ApiKeyStatusBadge extends StatelessWidget {
  const ApiKeyStatusBadge({super.key, required this.status});

  final ApiKeyStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isActive = status == ApiKeyStatus.active;
    final color = isActive ? AppColors.positiveAccent : AppColors.brandRed;
    final label = isActive
        ? l10n.apiKeysStatusActive
        : l10n.apiKeysStatusRevoked;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.innerGap,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
