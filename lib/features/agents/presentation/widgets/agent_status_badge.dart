import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/agent.dart';
import 'agent_avatar.dart';

/// Status pill for an agent — green for active, amber for pending,
/// slate for deactivated.
///
/// Shared by the agent list card and the detail screen so both surfaces
/// render the same affordance.
class AgentStatusBadge extends StatelessWidget {
  const AgentStatusBadge({super.key, required this.status});

  final AgentStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isActive = status == AgentStatus.active;
    final isPending = status == AgentStatus.pending;
    final color = agentStatusColor(isActive, isPending);
    final label = switch (status) {
      AgentStatus.active => l10n.agentsStatusActive,
      AgentStatus.pending => l10n.agentsStatusPending,
      AgentStatus.deactivated => l10n.agentsStatusDeactivated,
      AgentStatus.deactivating => l10n.agentsDeactivating,
    };

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
