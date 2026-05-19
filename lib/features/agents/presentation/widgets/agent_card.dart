import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/agent.dart';
import 'agent_avatar.dart';
import 'agent_format.dart';

/// A single tappable agent row on the list screen.
///
/// Shows the coloured avatar, the agent name, a status dot and a
/// status-aware subtitle ("Enrolled Feb 20" / "Pending approval" /
/// "Deactivated Feb 20"). Tapping the card opens the detail screen; all
/// actions live there, so the card itself carries no buttons.
class AgentCard extends StatelessWidget {
  const AgentCard({
    super.key,
    required this.agent,
    required this.onTap,
    this.selected = false,
  });

  final Agent agent;
  final VoidCallback onTap;

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
    final statusColor = agentStatusColor(agent.isActive, agent.isPending);

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
          child: Row(
            children: [
              AgentAvatar(agentId: agent.agentId, name: agent.name),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            agentDisplayName(l10n, agent),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.onSurface(brightness),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AgentStatusDot(color: statusColor),
                      ],
                    ),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
