import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/agent.dart';
import 'agent_avatar.dart';
import 'agent_format.dart';
import 'agent_status_badge.dart';

/// Agent identity and status; lifecycle dates belong in the detail view.
class AgentCard extends StatelessWidget {
  const AgentCard({
    super.key,
    required this.agent,
    required this.onTap,
    this.selected = false,
    this.compact = false,
  });

  final bool compact;
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

    if (compact) {
      return Material(
        color: selected
            ? AppColors.cardFooterOverlay(brightness)
            : AppColors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.cardPadding,
              vertical: AppSpacing.lg,
            ),
            child: Row(
              children: [
                AgentAvatar(
                  agentId: agent.agentId,
                  name: agent.name,
                  iconKey: agent.iconKey,
                  iconColor: agent.iconColor,
                ),
                const SizedBox(width: AppSpacing.fieldGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AgentCardIdentity(
                        agent: agent,
                        typeLabel: typeLabel,
                        brightness: brightness,
                        l10n: l10n,
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? AppColors.onSurface(brightness)
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
              color: AppColors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  child: Row(
                    children: [
                      AgentAvatar(
                        agentId: agent.agentId,
                        name: agent.name,
                        iconKey: agent.iconKey,
                        iconColor: agent.iconColor,
                      ),
                      const SizedBox(width: AppSpacing.innerGap),
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
            const SizedBox(width: AppSpacing.innerGap),
            AgentStatusBadge(status: agent.status),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
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
