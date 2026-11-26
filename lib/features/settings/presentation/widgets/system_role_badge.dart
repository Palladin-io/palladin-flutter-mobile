import '../../../../core/widgets/status_badge.dart';
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
  Widget build(BuildContext context) => StatusBadge(
    label: AppLocalizations.of(context)!.permissionsSystem,
    color: AppColors.onSurfaceMuted(Theme.of(context).brightness),
  );
}
