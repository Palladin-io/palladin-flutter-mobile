import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Keeps a role name and its optional system marker in one horizontal row.
class RoleNameRow extends StatelessWidget {
  const RoleNameRow({super.key, required this.name, required this.isSystem});

  final Widget name;
  final bool isSystem;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: name),
        if (isSystem) ...[
          const SizedBox(width: AppSpacing.innerGap),
          const SystemRoleBadge(),
        ],
      ],
    );
  }
}

/// Compact marker for Palladin-managed organization roles.
class SystemRoleBadge extends StatelessWidget {
  const SystemRoleBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)!.permissionsSystem;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.innerGap,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.vaultBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.vaultBlue.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.vaultBlue,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
