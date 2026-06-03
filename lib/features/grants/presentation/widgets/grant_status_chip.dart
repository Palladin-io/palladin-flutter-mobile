import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/grant.dart';
import 'grant_format.dart';

/// Small pill rendering a grant's status with a status-appropriate tint.
class GrantStatusChip extends StatelessWidget {
  const GrantStatusChip({super.key, required this.status});

  final GrantStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = _color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        grantStatusLabel(l10n, status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _color(GrantStatus status) {
    return switch (status) {
      GrantStatus.pending => AppColors.premiumAmber,
      GrantStatus.active => AppColors.positiveAccent,
      GrantStatus.denied ||
      GrantStatus.revoked ||
      GrantStatus.expired =>
        AppColors.brandRed,
    };
  }
}
