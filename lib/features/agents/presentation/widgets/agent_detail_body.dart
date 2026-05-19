import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/agent.dart';
import 'agent_avatar.dart';
import 'agent_format.dart';
import 'agent_status_badge.dart';

/// Scrollable detail body for a single agent.
///
/// Renders the hero card (avatar, name, status badge, public key, dates)
/// and the status-aware action zone:
/// - pending → green "Approve" zone
/// - active → red "Deactivate" danger zone
/// - deactivated → green "Reactivate" zone (no permanent delete — agents
///   are never deleted from the UI)
///
/// Reused unchanged by both the split-view detail pane and the pushed
/// full-screen detail page.
class AgentDetailBody extends StatelessWidget {
  const AgentDetailBody({
    super.key,
    required this.agent,
    required this.isMutating,
    required this.onApprove,
    required this.onDeactivate,
    required this.onReactivate,
  });

  final Agent agent;

  /// True while an approve / deactivate / reactivate for this agent is
  /// in flight — disables the action button and swaps its label for a
  /// spinner.
  final bool isMutating;

  final VoidCallback onApprove;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authState = context.watch<AuthBloc>().state;
    final permissions =
        authState is AuthAuthenticated ? authState.permissions : 0;
    final canManage = (permissions & Permissions.agentManage) != 0;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _HeroCard(agent: agent),
        if (canManage) ...[
          const SizedBox(height: 16),
          switch (agent.status) {
            AgentStatus.pending => _ApproveZone(
                isMutating: isMutating,
                onApprove: onApprove,
              ),
            AgentStatus.active => _DangerZone(
                label: l10n.agentsDeactivateZone,
                actionLabel: isMutating
                    ? l10n.agentsDeactivating
                    : l10n.agentsDeactivate,
                inFlight: isMutating,
                icon: Icons.block,
                onPressed: isMutating ? null : onDeactivate,
              ),
            AgentStatus.deactivated => _ReactivateZone(
                isMutating: isMutating,
                onReactivate: onReactivate,
              ),
          },
        ],
      ],
    );
  }
}

/// Hero card — avatar, name, status badge, public key suffix and the
/// enrolled / created dates.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.agent});

  final Agent agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AgentAvatar(
                agentId: agent.agentId,
                name: agent.name,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agentDisplayName(l10n, agent),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AgentStatusBadge(status: agent.status),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (agent.description != null &&
              agent.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              agent.description!.trim(),
              style: TextStyle(
                color: AppColors.onSurfaceMuted(brightness),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _DetailRow(
            label: l10n.agentsDetailPublicKey,
            value: agent.publicKeySuffix.isEmpty
                ? '—'
                : agent.publicKeySuffix,
            mono: true,
          ),
          const SizedBox(height: 8),
          _DetailRow(
            label: l10n.agentsDetailCreatedAt,
            value: formatAgentDate(agent.createdAt),
          ),
          if (agent.enrolledAt != null) ...[
            const SizedBox(height: 8),
            _DetailRow(
              label: l10n.agentsDetailEnrolledAt,
              value: formatAgentDate(agent.enrolledAt!),
            ),
          ],
          if (agent.enrolledByName != null &&
              agent.enrolledByName!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailRow(
              label: l10n.agentsDetailEnrolledBy,
              value: agent.enrolledByName!,
            ),
          ],
          if (agent.deactivatedAt != null) ...[
            const SizedBox(height: 8),
            _DetailRow(
              label: l10n.agentsDetailDeactivatedAt,
              value: formatAgentDate(agent.deactivatedAt!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Green-accented "approve" zone for a pending agent.
class _ApproveZone extends StatelessWidget {
  const _ApproveZone({required this.isMutating, required this.onApprove});

  final bool isMutating;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _AccentZone(
      color: AppColors.positiveAccent,
      label: l10n.agentsApproveZone,
      hint: l10n.agentsApproveHint,
      actionLabel: isMutating ? l10n.agentsApproving : l10n.agentsApprove,
      inFlight: isMutating,
      icon: Icons.check_circle_outline,
      onPressed: isMutating ? null : onApprove,
    );
  }
}

/// Green-accented "reactivate" zone for a deactivated agent.
class _ReactivateZone extends StatelessWidget {
  const _ReactivateZone({
    required this.isMutating,
    required this.onReactivate,
  });

  final bool isMutating;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _AccentZone(
      color: AppColors.positiveAccent,
      label: l10n.agentsReactivateZone,
      hint: l10n.agentsReactivateHint,
      actionLabel:
          isMutating ? l10n.agentsReactivating : l10n.agentsReactivate,
      inFlight: isMutating,
      icon: Icons.check_circle_outline,
      onPressed: isMutating ? null : onReactivate,
    );
  }
}

/// A coloured action card — a section label, a hint line and a single
/// full-width tinted action button. Used for both the green approve /
/// reactivate zones (positiveAccent) by [_ApproveZone] and
/// [_ReactivateZone].
class _AccentZone extends StatelessWidget {
  const _AccentZone({
    required this.color,
    required this.label,
    required this.hint,
    required this.actionLabel,
    required this.inFlight,
    required this.icon,
    required this.onPressed,
  });

  final Color color;
  final String label;
  final String hint;
  final String actionLabel;
  final bool inFlight;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: TextStyle(
              color: color,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton.icon(
              icon: inFlight
                  ? SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: color,
                      ),
                    )
                  : Icon(icon, size: 14, color: color),
              label: Text(
                actionLabel,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: color.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}

/// A red-bordered destructive-action card — a section label above a
/// single full-width tinted action button. Matches the danger-zone
/// pattern used on the API-key and vault settings screens.
class _DangerZone extends StatelessWidget {
  const _DangerZone({
    required this.label,
    required this.actionLabel,
    required this.inFlight,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String actionLabel;
  final bool inFlight;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.brandRed,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton.icon(
              icon: inFlight
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.brandRed,
                      ),
                    )
                  : Icon(icon, size: 14, color: AppColors.brandRed),
              label: Text(
                actionLabel,
                style: const TextStyle(
                  color: AppColors.brandRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.brandRed.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single label / value row inside the hero card.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;

  /// When true, renders [value] in a monospace font — used for the
  /// public key suffix.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}
