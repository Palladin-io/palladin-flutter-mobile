import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/agent.dart';
import 'agent_avatar.dart';
import 'agent_format.dart';
import 'agent_status_badge.dart';
import 'approve_agent_sheet.dart';

/// A single tappable agent row on the list screen.
///
/// Shows the coloured avatar, the agent name, a status dot, a
/// status-aware subtitle ("Enrolled Feb 20" / "Pending approval" /
/// "Deactivated Feb 20"), the abbreviated public key and — for pending
/// agents — an inline "Approve" button. Tapping the card opens the
/// detail screen.
class AgentCard extends StatelessWidget {
  const AgentCard({
    super.key,
    required this.agent,
    required this.onTap,
    this.onApprove,
    this.selected = false,
  });

  final Agent agent;
  final VoidCallback onTap;

  /// Invoked when the inline "Approve" button is tapped on a pending
  /// agent. When `null` the button is hidden — e.g. for a viewer who
  /// lacks the manage permission.
  final VoidCallback? onApprove;

  /// When true the card is highlighted — used by the split-view layout
  /// to indicate which agent is open in the detail pane.
  final bool selected;

  String _subtitle(AppLocalizations l10n) {
    return switch (agent.status) {
      AgentStatus.pending => l10n.agentsPendingApproval,
      AgentStatus.active => agent.enrolledAt != null
          ? '${l10n.agentsEnrolled} ${formatAgentDate(agent.enrolledAt!)}'
          : l10n.agentsStatusActive,
      AgentStatus.deactivated => agent.deactivatedAt != null
          ? '${l10n.agentsDeactivated} '
              '${formatAgentDate(agent.deactivatedAt!)}'
          : l10n.agentsStatusDeactivated,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final showApprove = agent.isPending && onApprove != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.brandRed.withValues(alpha: 0.5)
                  : AppColors.cardBorder(brightness),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AgentAvatar(agentId: agent.agentId, name: agent.name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          agentDisplayName(l10n, agent),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.onSurface(brightness),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AgentStatusBadge(status: agent.status),
                        const SizedBox(height: 4),
                        Text(
                          _subtitle(l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.onSurfaceSubtle(brightness),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          agent.publicKeyDisplay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.onSurfaceSubtle(brightness),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: ${agent.agentId.length > 8 ? agent.agentId.substring(0, 8) : agent.agentId}…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.onSurfaceSubtle(brightness),
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (showApprove) ...[
                const SizedBox(height: 10),
                _InlineApproveButton(onPressed: onApprove!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact green "Approve" button shown on a pending agent's card.
/// Reuses [ApproveActionButton] so card / sheet / detail action zone
/// stay visually identical.
class _InlineApproveButton extends StatelessWidget {
  const _InlineApproveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ApproveActionButton(
      label: l10n.agentsApprove,
      onPressed: onPressed,
      height: 36,
    );
  }
}
