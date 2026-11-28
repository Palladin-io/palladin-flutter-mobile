import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../settings/domain/entities/api_key.dart';

/// Outlined status badge for an API key — green for active, red for revoked.
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

    return StatusBadge(label: label, color: color);
  }
}
