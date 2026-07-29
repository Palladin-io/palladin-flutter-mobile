import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';

/// Result of the revoke confirmation sheet.
class RevokeGrantResult {
  const RevokeGrantResult();
}

/// Confirmation bottom sheet shown before revoking a grant.
///
/// Resolves to a [RevokeGrantResult] when confirmed, or `null` when the
/// user cancels / dismisses.
class RevokeGrantSheet extends StatelessWidget {
  const RevokeGrantSheet({super.key, required this.agentName});

  final String agentName;

  static Future<RevokeGrantResult?> show(
    BuildContext context,
    String agentName,
  ) {
    return showModalBottomSheet<RevokeGrantResult>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RevokeGrantSheet(agentName: agentName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.sm,
              AppSpacing.screenH,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.onSurfaceSubtle(
                        brightness,
                      ).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.headerGap),
                Text(
                  l10n.grantsRevokeConfirmTitle,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.innerGap),
                Text(
                  l10n.grantsRevokeConfirmBody(agentName),
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          SheetActionButtons(
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: () =>
                Navigator.of(context).pop(const RevokeGrantResult()),
            confirmLabel: l10n.grantsRevoke,
            confirmColor: AppColors.brandRed,
          ),
        ],
      ),
    );
  }
}
