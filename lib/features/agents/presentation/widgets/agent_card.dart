import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/agent.dart';
import 'agent_avatar.dart';
import 'agent_format.dart';
import 'agent_status_badge.dart';

/// A single tappable agent row on the list screen.
///
/// The card has two zones:
///
/// * An identification zone (tappable) — avatar, name + status badge,
///   and a subtitle line that prefers the localized agent type when
///   set and falls back to the monospaced agent ID.
/// * A footer (non-tappable) — separator, an icon and a short status
///   line summarizing the agent's lifecycle (deactivated, last access,
///   enrolled, or first connected — in that order of priority).
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final typeLabel = agentTypeLabel(l10n, agent.type);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? AppColors.brandRed.withValues(alpha: 0.5)
              : AppColors.cardBorder(brightness),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Identification zone — tappable.
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      AgentAvatar(
                        agentId: agent.agentId,
                        name: agent.name,
                        iconKey: agent.iconKey,
                        iconColor: agent.iconColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AgentCardIdentity(
                          agent: agent,
                          typeLabel: typeLabel,
                          brightness: brightness,
                          l10n: l10n,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _AgentCardFooter(agent: agent, brightness: brightness),
          ],
        ),
      ),
    );
  }
}

/// The identification block — name + status badge on top, then either
/// the localized type label and a small monospaced ID, or (when the
/// agent has no type) the full monospaced agent ID alone.
class _AgentCardIdentity extends StatelessWidget {
  const _AgentCardIdentity({
    required this.agent,
    required this.typeLabel,
    required this.brightness,
    required this.l10n,
  });

  final Agent agent;
  final String? typeLabel;
  final Brightness brightness;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AgentStatusBadge(status: agent.status),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          typeLabel ?? l10n.agentsTypeUnknown,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// The non-tappable card footer — sits below the identification block,
/// separated by a hairline top border and a near-transparent overlay
/// fill. Shows a single lifecycle status line (deactivated / last access
/// / enrolled / connected) plus an icon on the left.
class _AgentCardFooter extends StatelessWidget {
  const _AgentCardFooter({
    required this.agent,
    required this.brightness,
  });

  final Agent agent;
  final Brightness brightness;

  /// Resolves the footer label using the same priority order as the
  /// web panel:
  ///   1. Deactivated + `deactivatedAt`
  ///   2. `lastAccessAt`
  ///   3. `enrolledAt`
  ///   4. fallback to `createdAt` ("Connected on ...")
  String _footerText(AppLocalizations l10n, String locale) {
    if (agent.isDeactivated && agent.deactivatedAt != null) {
      final base =
          '${l10n.agentsDeactivatedOn} ${formatAgentDate(agent.deactivatedAt!, locale)}';
      final by = agent.deactivatedByName;
      return by != null && by.isNotEmpty ? '$base · $by' : base;
    }
    if (agent.enrolledAt != null) {
      final base =
          '${l10n.agentsEnrolled} ${formatAgentDate(agent.enrolledAt!, locale)}';
      final by = agent.enrolledByName;
      return by != null && by.isNotEmpty ? '$base · $by' : base;
    }
    return '${l10n.agentsConnectedOn} ${formatAgentDate(agent.createdAt, locale)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final isDeactivated = agent.isDeactivated;
    final iconData = isDeactivated ? Icons.block : Icons.schedule;
    final iconColor = isDeactivated
        ? AppColors.brandRed
        : AppColors.onSurfaceSubtle(brightness);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFooterOverlay(brightness),
        border: Border(
          top: BorderSide(
            color: AppColors.cardBorder(brightness),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(iconData, size: 12, color: iconColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _footerText(l10n, locale),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
