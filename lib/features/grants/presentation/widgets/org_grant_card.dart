import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../agents/presentation/widgets/agent_avatar.dart';
import '../../domain/entities/grant.dart';
import '../grant_method_label.dart';
import 'grant_format.dart';

/// Rich grant card for the Approvals "history" feed — the mobile counterpart
/// of the web `OrgGrantRow`. An agent identity row (avatar + name + status pill
/// + relative time) over a fixed set of detail rows (Entry/Vault · By · Access
/// · contextual Reason) so every card is the same height, then a footer with
/// the available action. Terminal history either offers re-granting, links to
/// the newer active grant, or links to the inactive Agent/context.
class OrgGrantCard extends StatelessWidget {
  const OrgGrantCard({
    super.key,
    required this.grant,
    required this.onRevoke,
    required this.onRegrant,
    required this.onReviewPending,
    required this.onShowActiveGrant,
    required this.onViewContext,
    this.isRevoking = false,
  });

  final Grant grant;
  final VoidCallback onRevoke;
  final VoidCallback onRegrant;
  final VoidCallback onReviewPending;
  final VoidCallback onShowActiveGrant;
  final VoidCallback onViewContext;
  final bool isRevoking;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final isFull = grant.scope == GrantScope.full;
    final reason = orgGrantContextualReason(l10n, grant);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _IdentityRow(grant: grant),
            _Divider(brightness: brightness),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.cardPadding,
                vertical: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFull)
                    GrantDetailRow(
                      label: l10n.orgGrantRowVault,
                      value: grant.vaultName ?? l10n.approvalVaultUnknown,
                    )
                  else
                    GrantDetailRow(
                      label: l10n.orgGrantRowEntry,
                      value: _entryValue(l10n),
                    ),
                  const SizedBox(height: AppSpacing.innerGap),
                  GrantDetailRow(
                    label: l10n.orgGrantRowActor,
                    value: orgGrantActorName(l10n, grant),
                  ),
                  const SizedBox(height: AppSpacing.innerGap),
                  GrantDetailRow(
                    label: l10n.orgGrantRowAccess,
                    value: orgGrantAccessSummary(l10n, grant),
                  ),
                  if (grant.methods.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.innerGap),
                    GrantDetailRow(
                      label: l10n.orgGrantRowMethods,
                      value: grant.methods
                          .map((m) => grantMethodLabel(l10n, m))
                          .join(' · '),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.innerGap),
                  GrantDetailRow(label: reason.label, value: reason.text),
                ],
              ),
            ),
            _Footer(
              grant: grant,
              isRevoking: isRevoking,
              onRevoke: onRevoke,
              onRegrant: onRegrant,
              onReviewPending: onReviewPending,
              onShowActiveGrant: onShowActiveGrant,
              onViewContext: onViewContext,
              brightness: brightness,
            ),
          ],
        ),
      ),
    );
  }

  String _entryValue(AppLocalizations l10n) {
    final entry = grant.entryLabel ?? l10n.grantEntryUnknown;
    final vault = grant.vaultName;
    return vault != null && vault.isNotEmpty ? '$entry · $vault' : entry;
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({required this.grant});

  final Grant grant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final color = grantStatusColor(grant.status);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.innerGap,
      ),
      child: Row(
        children: [
          AgentAvatar(
            agentId: grant.agentId ?? '',
            name: grant.agentName,
            iconKey: grant.agentIconKey,
            size: 28,
          ),
          const SizedBox(width: AppSpacing.innerGap),
          Expanded(
            child: Text(
              grantAgentDisplayName(l10n, grant),
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
          _StatusPill(status: grant.status, color: color),
          const SizedBox(width: AppSpacing.innerGap),
          Text(
            grantRelativeTime(l10n, grant.createdAt),
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.color});

  final GrantStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.innerGap,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            grantStatusLabel(l10n, status),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// One labelled row inside a grant card — muted fixed-width label + a
/// single-line truncated value. Shared by the org-grant (history) card and the
/// pending-approval card so both line up identically (web `DetailRow`).
class GrantDetailRow extends StatelessWidget {
  const GrantDetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.innerGap),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.grant,
    required this.isRevoking,
    required this.onRevoke,
    required this.onRegrant,
    required this.onReviewPending,
    required this.onShowActiveGrant,
    required this.onViewContext,
    required this.brightness,
  });

  final Grant grant;
  final bool isRevoking;
  final VoidCallback onRevoke;
  final VoidCallback onRegrant;
  final VoidCallback onReviewPending;
  final VoidCallback onShowActiveGrant;
  final VoidCallback onViewContext;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Actions are driven strictly by the backend capability flags.
    if (grant.status == GrantStatus.pending) {
      return _FooterShell(
        brightness: brightness,
        child: _FilledFooterAction(
          label: l10n.orgGrantReviewRequest,
          onPressed: onReviewPending,
          backgroundColor: AppColors.brandRed,
        ),
      );
    }

    if (grant.canRevoke) {
      return _FooterShell(
        brightness: brightness,
        child: _RevokeButton(isRevoking: isRevoking, onRevoke: onRevoke),
      );
    }

    if (grant.canGrantAgain) {
      return _FooterShell(
        brightness: brightness,
        child: _FilledFooterAction(
          label: l10n.approvalRegrant,
          onPressed: onRegrant,
          backgroundColor: AppColors.positiveAccent,
        ),
      );
    }

    if (grant.status.isTerminal) {
      final hasActiveCoverage = grant.activeCoveringGrantIds.isNotEmpty;
      return _FooterShell(
        brightness: brightness,
        child: _FooterInfoAction(
          icon: hasActiveCoverage ? Icons.check_circle : Icons.info_outline,
          color: hasActiveCoverage
              ? AppColors.positiveAccent
              : AppColors.onSurfaceSubtle(brightness),
          message: hasActiveCoverage
              ? l10n.orgGrantAlreadyActive
              : l10n.orgGrantRegrantUnavailable,
          actionLabel: hasActiveCoverage
              ? l10n.orgGrantShowActive
              : grant.agentId != null
              ? l10n.orgGrantViewAgent
              : l10n.orgGrantViewVault,
          onPressed: hasActiveCoverage ? onShowActiveGrant : onViewContext,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _FooterInfoAction extends StatelessWidget {
  const _FooterInfoAction({
    required this.icon,
    required this.color,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.chipGap),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.chipGap),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: color,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
          child: Text(
            actionLabel,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _FilledFooterAction extends StatelessWidget {
  const _FilledFooterAction({
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
  });

  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: AppColors.onBrandRed,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _FooterShell extends StatelessWidget {
  const _FooterShell({required this.brightness, required this.child});

  final Brightness brightness;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      decoration: BoxDecoration(
        color: AppColors.cardFooterOverlay(brightness),
        border: Border(
          top: BorderSide(color: AppColors.cardBorder(brightness)),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.innerGap,
      ),
      child: Center(child: child),
    );
  }
}

class _RevokeButton extends StatelessWidget {
  const _RevokeButton({required this.isRevoking, required this.onRevoke});

  final bool isRevoking;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: OutlinedButton(
        onPressed: isRevoking ? null : onRevoke,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brandRed,
          side: const BorderSide(color: AppColors.brandRed),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: isRevoking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brandRed,
                ),
              )
            : Text(
                l10n.grantsRevoke,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppColors.cardBorder(brightness),
    );
  }
}
