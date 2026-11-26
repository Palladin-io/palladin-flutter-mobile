import 'package:flutter/material.dart';

import '../../../../core/widgets/status_badge.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/agent.dart';
import 'agent_avatar.dart';

/// Outlined status badge for an agent — green for active, amber for pending,
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

    return StatusBadge(label: label, color: color);
  }
}
