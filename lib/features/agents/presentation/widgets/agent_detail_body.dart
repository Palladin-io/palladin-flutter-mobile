import 'package:flutter/material.dart';

import '../../../../core/widgets/brand_tab_indicator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/approve_action_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../approval/presentation/widgets/grant_access_sheet.dart';
import '../../../grants/presentation/widgets/context_grants_tab.dart';
import '../../domain/entities/agent.dart';
import 'agent_avatar.dart';
import 'agent_edit_form.dart';
import 'agent_format.dart';
import 'agent_status_badge.dart';

/// Tab segments shown on the agent detail screen — mirrors the web
/// panel's `AgentDetail` so the two surfaces feel consistent.
enum _AgentDetailTab { details, grants, logs }

/// Scrollable detail body for a single agent.
///
/// Mirrors the web panel's `AgentDetail`:
/// 1. **Tab bar** (Details / Grants / Logs). Grants is disabled until
///    the agent is active. The active tab is underlined in brand red.
/// 2. **Details tab** — hero card (avatar + name + status badge), an
///    always-visible edit form (name + type + description), a read-only
///    metadata list (public key, connected on, enrolled, deactivated)
///    and a status-aware action zone (approve / deactivate / reactivate).
/// 3. **Grants tab** — empty card placeholder until the grants module
///    ships its mobile UI.
/// 4. **Logs tab** — lifecycle timeline derived from the agent's dates.
///
/// Reused unchanged by both the split-view detail pane and the pushed
/// full-screen detail page.
class AgentDetailBody extends StatefulWidget {
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
  State<AgentDetailBody> createState() => _AgentDetailBodyState();
}

class _AgentDetailBodyState extends State<AgentDetailBody> {
  _AgentDetailTab _activeTab = _AgentDetailTab.details;

  // Bumped after a grant is created so the (self-providing) grants list remounts and reloads.
  int _grantsRefresh = 0;

  Future<void> _onAddGrant() async {
    final granted = await GrantAccessSheet.show(
      context,
      GrantForAgent(widget.agent.agentId),
    );
    if (granted == true && mounted) {
      setState(() => _grantsRefresh++);
    }
  }

  @override
  void didUpdateWidget(AgentDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Snap back to Details whenever the user navigates to a different
    // agent so the tab does not leak across selections (the split view
    // mounts a single body and only swaps the [agent] prop).
    if (oldWidget.agent.agentId != widget.agent.agentId) {
      _activeTab = _AgentDetailTab.details;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final permissions = authState is AuthAuthenticated
        ? authState.permissions
        : 0;
    final canManage = (permissions & Permissions.agentManage) != 0;

    final l10n = AppLocalizations.of(context)!;

    // Grants and Logs are meaningless for an agent that has never been
    // active — a pending agent has no grants and no activity yet. Lock
    // those tabs (greyed out) and keep the view pinned to Details.
    final lockedTabs = widget.agent.isPending;
    final activeTab = lockedTabs && _activeTab != _AgentDetailTab.details
        ? _AgentDetailTab.details
        : _activeTab;

    // Fixed tab bar + scrolling content (Expanded) — so the Grants tab can host its own scrollable
    // list (ContextGrantsTab). The host gives this body a bounded height (split-view pane).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header (pane title / AppBar) → tab bar: headerGap. Owned here so the
        // split-view pane and the pushed page share one rhythm.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.headerGap,
            AppSpacing.screenH,
            0,
          ),
          child: _TabBar(
            active: activeTab,
            lockedTabs: lockedTabs,
            onSelected: (tab) => setState(() => _activeTab = tab),
          ),
        ),
        // Tab bar → content: fieldGap.
        const SizedBox(height: AppSpacing.fieldGap),
        Expanded(
          child: switch (activeTab) {
            _AgentDetailTab.details => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                0,
                AppSpacing.screenH,
                AppSpacing.screenBottom,
              ),
              children: [
                _DetailsCard(agent: widget.agent, canEdit: canManage),
                if (canManage) ...[
                  const SizedBox(height: AppSpacing.cardPadding),
                  _ActionZone(
                    agent: widget.agent,
                    isMutating: widget.isMutating,
                    onApprove: widget.onApprove,
                    onDeactivate: widget.onDeactivate,
                    onReactivate: widget.onReactivate,
                  ),
                ],
              ],
            ),
            _AgentDetailTab.grants => Stack(
              children: [
                ContextGrantsTab(
                  key: ValueKey(_grantsRefresh),
                  agentId: widget.agent.agentId,
                  emptyTitle: l10n.agentGrantsEmptyTitle,
                  emptyHint: l10n.agentGrantsEmptyHint,
                ),
                if (canManage)
                  Positioned(
                    right: AppSpacing.headerGap,
                    bottom: AppSpacing.headerGap,
                    child: AppFab(
                      onPressed: _onAddGrant,
                      tooltip: l10n.grantAddGrant,
                    ),
                  ),
              ],
            ),
            _AgentDetailTab.logs => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                0,
                AppSpacing.screenH,
                AppSpacing.screenBottom,
              ),
              children: [_LogsCard(agent: widget.agent)],
            ),
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Tab bar
// ─────────────────────────────────────────────────────────────────────────

/// Underlined tab bar — mirrors the web entry/agent detail pattern.
///
/// Active tab gets a brand-red underline + bold label; inactive tabs use
/// the muted surface tint. The Grants tab is disabled until the agent
/// reaches the active state.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.active,
    required this.lockedTabs,
    required this.onSelected,
  });

  final _AgentDetailTab active;

  /// When true the Grants and Logs tabs are greyed out and unselectable —
  /// the agent is still pending so neither has any content yet.
  final bool lockedTabs;
  final ValueChanged<_AgentDetailTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    final tabs = <({_AgentDetailTab tab, String label, bool disabled})>[
      (
        tab: _AgentDetailTab.details,
        label: l10n.agentsTabDetails,
        disabled: false,
      ),
      (
        tab: _AgentDetailTab.grants,
        label: l10n.agentsTabGrants,
        disabled: lockedTabs,
      ),
      (
        tab: _AgentDetailTab.logs,
        label: l10n.agentsTabLogs,
        disabled: lockedTabs,
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder(brightness)),
        ),
      ),
      child: Row(
        children: [
          for (final t in tabs)
            _TabButton(
              label: t.label,
              isActive: active == t.tab,
              disabled: t.disabled,
              onTap: () => onSelected(t.tab),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.isActive,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    final color = disabled
        ? AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.4)
        : isActive
        ? AppColors.brandRed
        : AppColors.onSurfaceSubtle(brightness);

    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.fieldGap,
          vertical: AppSpacing.cardGap,
        ),
        decoration: isActive && !disabled
            ? BrandTabIndicator(glowColor: AppColors.primaryGlow(brightness))
            : null,
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Details tab — hero card with edit form + read-only metadata
// ─────────────────────────────────────────────────────────────────────────

/// Card holding the identity header, the editable form and the read-only
/// metadata list. Mirrors the web panel `AgentDetail` "Details" tab.
///
/// On mobile we take a stricter stance than the web panel: the inline
/// edit form is only shown for **active** agents. Pending and
/// deactivated agents render the identity header and metadata list
/// only — keeping the surface focused on the next available action
/// (approve / reactivate) which lives in the [_ActionZone] below.
class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.agent, required this.canEdit});

  final Agent agent;

  /// True when the operator may edit the agent — derived from the
  /// `agentManage` permission.
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    // Mirror web semantics: form is editable only for an active agent
    // held by an operator with manage permission. The mobile surface
    // takes one extra step and hides the form entirely for non-active
    // agents (pending / deactivated) — the approve / reactivate CTA in
    // the action zone covers the available next step.
    final showEditForm = canEdit && agent.isActive;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IdentityHeader(agent: agent),
          const SizedBox(height: AppSpacing.cardPadding),
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.cardBorder(brightness),
          ),
          const SizedBox(height: AppSpacing.cardPadding),
          _MetadataList(agent: agent, l10n: l10n),
          if (showEditForm) ...[
            const SizedBox(height: AppSpacing.cardPadding),
            Divider(
              height: 1,
              thickness: 1,
              color: AppColors.cardBorder(brightness),
            ),
            const SizedBox(height: AppSpacing.cardPadding),
            AgentEditForm(agent: agent, canEdit: true),
          ],
        ],
      ),
    );
  }
}

/// Identity header — avatar + name + status badge.
///
/// Layout: `[avatar] [name / status-badge]` — badge sits under the name.
class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.agent});

  final Agent agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AgentAvatar(
          agentId: agent.agentId,
          name: agent.name,
          iconKey: agent.iconKey,
          iconColor: agent.iconColor,
          size: 40,
        ),
        const SizedBox(width: AppSpacing.fieldGap),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              AgentStatusBadge(status: agent.status),
            ],
          ),
        ),
      ],
    );
  }
}

/// Read-only metadata list — public key + connected / enrolled /
/// deactivated dates. Renders only the rows that have data, in the same
/// order as the web panel.
class _MetadataList extends StatelessWidget {
  const _MetadataList({required this.agent, required this.l10n});

  final Agent agent;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final rows = <Widget>[
      _DetailRow(label: l10n.agentsDetailId, value: agent.agentId, mono: true),
      _DetailRow(
        label: l10n.agentsDetailPublicKey,
        value: agent.publicKeyDisplay,
        mono: true,
      ),
      if (agent.enrolledAt != null)
        _DetailRow(
          label: l10n.agentsDetailEnrolledAt,
          value: _withSignedBy(
            formatAgentDate(agent.enrolledAt!, locale),
            agent.enrolledByName,
          ),
        ),
      if (agent.deactivatedAt != null)
        _DetailRow(
          label: l10n.agentsDetailDeactivatedAt,
          value: _withSignedBy(
            formatAgentDate(agent.deactivatedAt!, locale),
            agent.deactivatedByName,
          ),
        ),
      if (agent.lastIp != null)
        _DetailRow(
          label: l10n.agentsDetailLastIp,
          value: agent.lastIp!,
          mono: true,
        ),
      if (agent.lastHostname != null)
        _DetailRow(
          label: l10n.agentsDetailLastHostname,
          value: agent.lastHostname!,
        ),
      _DetailRow(
        label: l10n.agentsDetailCreatedAt,
        value: formatAgentDateTime(agent.createdAt, locale),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.cardGap),
          rows[i],
        ],
      ],
    );
  }

  /// Appends `· {name}` after the formatted date when an attribution
  /// name is available — mirrors the web "{date} · {name}" pattern.
  String _withSignedBy(String date, String? name) {
    if (name == null || name.trim().isEmpty) return date;
    return '$date · ${name.trim()}';
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Action zones — approve / deactivate / reactivate
// ─────────────────────────────────────────────────────────────────────────

/// Status-aware action zone shown below the details card.
///
/// - `pending`     → green Approve zone with the approve CTA
/// - `active`      → red Danger zone with the deactivate CTA
/// - `deactivated` → green Reactivate zone with the reactivate CTA
class _ActionZone extends StatelessWidget {
  const _ActionZone({
    required this.agent,
    required this.isMutating,
    required this.onApprove,
    required this.onDeactivate,
    required this.onReactivate,
  });

  final Agent agent;
  final bool isMutating;
  final VoidCallback onApprove;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (agent.status) {
      AgentStatus.pending => _PositiveZone(
        title: l10n.agentsApproveZone,
        hint: l10n.agentsApproveHint,
        actionLabel: isMutating ? l10n.agentsApproving : l10n.agentsApprove,
        isLoading: isMutating,
        onPressed: isMutating ? null : onApprove,
      ),
      AgentStatus.active => _DangerZone(
        title: l10n.agentsDeactivateZone,
        heading: l10n.agentsDeactivate,
        hint: l10n.agentsDeactivateHint,
        actionLabel: isMutating
            ? l10n.agentsDeactivating
            : l10n.agentsDeactivate,
        isLoading: isMutating,
        onPressed: isMutating ? null : onDeactivate,
      ),
      AgentStatus.deactivated => _PositiveZone(
        title: l10n.agentsReactivateZone,
        hint: l10n.agentsReactivateHint,
        actionLabel: isMutating
            ? l10n.agentsReactivating
            : l10n.agentsReactivate,
        isLoading: isMutating,
        onPressed: isMutating ? null : onReactivate,
      ),
      AgentStatus.deactivating => const SizedBox.shrink(),
    };
  }
}

/// Green-accented zone (approve / reactivate). Mirrors the web web
/// `ActionZone tone="positive"` card.
class _PositiveZone extends StatelessWidget {
  const _PositiveZone({
    required this.title,
    required this.hint,
    required this.actionLabel,
    required this.isLoading,
    required this.onPressed,
  });

  final String title;
  final String hint;
  final String actionLabel;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.positiveAccent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.positiveAccent.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.positiveAccent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            hint,
            style: TextStyle(
              color: AppColors.positiveAccent.withValues(alpha: 0.85),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          ApproveActionButton(
            label: actionLabel,
            onPressed: onPressed,
            isLoading: isLoading,
          ),
        ],
      ),
    );
  }
}

/// Red-bordered destructive-action card — section label, a heading + hint
/// and the full-width deactivate CTA.
class _DangerZone extends StatelessWidget {
  const _DangerZone({
    required this.title,
    required this.heading,
    required this.hint,
    required this.actionLabel,
    required this.isLoading,
    required this.onPressed,
  });

  final String title;
  final String heading;
  final String hint;
  final String actionLabel;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.brandRed.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.brandRed,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppSpacing.chipGap),
          Text(
            heading,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            hint,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton.icon(
              icon: isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.brandRed,
                      ),
                    )
                  : const Icon(
                      Icons.block,
                      size: 16,
                      color: AppColors.brandRed,
                    ),
              label: Text(
                actionLabel,
                style: const TextStyle(
                  color: AppColors.brandRed,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.brandRed.withValues(alpha: 0.12),
                disabledBackgroundColor: AppColors.brandRed.withValues(
                  alpha: 0.06,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: AppColors.brandRed.withValues(alpha: 0.3),
                  ),
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

// ─────────────────────────────────────────────────────────────────────────
// Logs tab — lifecycle timeline
// ─────────────────────────────────────────────────────────────────────────

/// Lifecycle timeline derived from the agent's dates — first connected,
/// enrolled, deactivated.
class _LogsCard extends StatelessWidget {
  const _LogsCard({required this.agent});

  final Agent agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final locale = Localizations.localeOf(context).toString();

    final entries = <({String label, DateTime date, String? detail})>[
      (
        label: l10n.agentsLogsFirstConnected,
        date: agent.createdAt,
        detail: null,
      ),
      if (agent.enrolledAt != null)
        (
          label: l10n.agentsLogsEnrolled,
          date: agent.enrolledAt!,
          detail: agent.enrolledByName,
        ),
      if (agent.deactivatedAt != null)
        (
          label: l10n.agentsLogsDeactivated,
          date: agent.deactivatedAt!,
          detail: agent.deactivatedByName,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: AppColors.cardBorder(brightness),
              ),
            _LogRow(
              label: entries[i].label,
              date: formatAgentDate(entries[i].date, locale),
              detail: entries[i].detail,
            ),
          ],
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.label, required this.date, this.detail});

  final String label;
  final String date;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.cardGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            // Nudges the bullet down to align with the first text line.
            margin: const EdgeInsets.only(top: 5),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
          ),
          const SizedBox(width: AppSpacing.cardGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null && detail!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    detail!.trim(),
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            date,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Detail row — label + value, used inside the metadata list
// ─────────────────────────────────────────────────────────────────────────

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
        const SizedBox(width: AppSpacing.fieldGap),
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
