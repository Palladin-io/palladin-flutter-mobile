import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../approval/domain/entities/pending_grant.dart';

/// Red-bordered card surfacing a grant request from an agent that is not
/// yet enrolled. The owner can register the agent and approve access in
/// one step, or reject the request.
class UnknownAgentCard extends StatelessWidget {
  const UnknownAgentCard({
    super.key,
    required this.grant,
    required this.onRegisterApprove,
    required this.onReject,
  });

  final PendingGrant grant;
  final VoidCallback onRegisterApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    final agentLabel = grant.agentName ?? grant.agentId;
    final contextLabel = grant.vaultName ?? grant.entryLabel;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Warning header bar.
          Container(
            color: AppColors.brandRed.withValues(alpha: 0.06),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.fieldGap,
              vertical: AppSpacing.chipGap,
            ),
            child: Row(
              children: [
                const Icon(Icons.warning, size: 14, color: AppColors.brandRed),
                const SizedBox(width: AppSpacing.chipGap),
                Text(
                  l10n.dashboardUnknownAgentWarning,
                  style: const TextStyle(
                    color: AppColors.brandRed,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Body.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.fieldGap,
              AppSpacing.cardGap,
              AppSpacing.fieldGap,
              AppSpacing.innerGap,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DashedAgentIcon(),
                const SizedBox(width: AppSpacing.innerGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              agentLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.onSurface(brightness),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.innerGap),
                          Text(
                            _relativeTime(l10n, grant.createdAt),
                            style: TextStyle(
                              color: AppColors.onSurfaceSubtle(brightness),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      if (contextLabel != null && contextLabel.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          contextLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.onSurfaceSubtle(brightness),
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.innerGap),
                      Text(
                        l10n.dashboardUnknownAgentDescription,
                        style: TextStyle(
                          color: AppColors.onSurfaceSubtle(brightness),
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Footer actions.
          Container(
            color: AppColors.textTertiary.withValues(alpha: 0.06),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.fieldGap,
              vertical: AppSpacing.innerGap,
            ),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      onPressed: onRegisterApprove,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.approveGreen,
                        foregroundColor: AppColors.onBrandRed,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.innerGap,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        l10n.dashboardUnknownAgentRegisterAndApprove,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.chipGap),
                SizedBox(
                  height: 32,
                  child: TextButton(
                    onPressed: onReject,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandRed,
                      backgroundColor: AppColors.brandRed.withValues(
                        alpha: 0.1,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.cardGap,
                      ),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      l10n.dashboardUnknownAgentReject,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Localised relative timestamp, reusing the vault list's time keys.
  String _relativeTime(AppLocalizations l10n, DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return l10n.vaultUpdatedNow;
    if (diff.inMinutes < 60) return l10n.vaultUpdatedMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.vaultUpdatedHoursAgo(diff.inHours);
    return l10n.vaultUpdatedDaysAgo(diff.inDays);
  }
}

/// 32×32 dashed-border square holding the agent glyph — signals an
/// unrecognised / not-yet-registered agent.
class _DashedAgentIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.smart_toy, size: 14, color: AppColors.brandRed),
    );
  }
}
