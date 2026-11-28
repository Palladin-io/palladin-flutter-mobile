import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../bloc/agents_cubit.dart';
import '../../../vault/presentation/widgets/entry_field_row.dart';
import '../../../../core/di/injection.dart';
import '../../../audit/domain/entities/audit_log_entry.dart';
import '../../../audit/domain/repositories/audit_repository.dart';
import '../../../audit/presentation/audit_presentation_resolver.dart';
import '../../../audit/presentation/cubit/audit_log_cubit.dart';
import '../../../audit/presentation/widgets/audit_log_content.dart';
import '../../../../core/widgets/action_zone.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/app_detail_tabs.dart';
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
import 'agent_edit_form.dart';
import 'agent_format.dart';

/// Tab segments shown on the agent detail screen — mirrors the web
/// panel's `AgentDetail` so the two surfaces feel consistent.
enum _AgentDetailTab { details, grants, logs }

/// Scrollable detail body for a single agent.
///
/// Shared tabs host read-only metadata, grants and an agent-scoped audit feed.
/// Identity and status belong in the page header; Edit opens a root form.
/// Pending agents cannot open grants or logs, and audit access stays permission-gated.
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

class _AgentDetailBodyState extends State<AgentDetailBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

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

  void _onEdit() {
    final cubit = context.read<AgentsCubit>();
    final l10n = AppLocalizations.of(context)!;
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => MultiBlocProvider(
          providers: [
            BlocProvider<AgentsCubit>.value(value: cubit),
            BlocProvider<AuthBloc>.value(value: context.read<AuthBloc>()),
          ],
          child: AppScreen.appBar(
            safeAreaBottom: false,
            appBar: AppBar(
              titleSpacing: 0,
              centerTitle: false,
              title: AppBarTitle(title: l10n.agentsEditTitle),
            ),
            body: Builder(
              builder: (editorContext) {
                final session = editorContext.watch<AuthBloc>().state;
                final current = editorContext
                    .watch<AgentsCubit>()
                    .state
                    .agentById(widget.agent.agentId);
                final canEdit =
                    session is AuthAuthenticated &&
                    !session.isVaultLocked &&
                    (session.permissions & Permissions.agentManage) != 0 &&
                    current?.isActive == true;
                return AgentEditForm(
                  agent: current ?? widget.agent,
                  canEdit: canEdit,
                  fullScreen: true,
                  onSaved: () => Navigator.of(routeContext).pop(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(AgentDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Snap back to Details whenever the user navigates to a different
    // agent so the tab does not leak across selections (the split view
    // mounts a single body and only swaps the [agent] prop).
    if (oldWidget.agent.agentId != widget.agent.agentId) {
      _activeTab = _AgentDetailTab.details;
      _tabs.index = 0;
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
    final activeTab =
        (lockedTabs && _activeTab != _AgentDetailTab.details) ||
            (_activeTab == _AgentDetailTab.logs &&
                (permissions & Permissions.auditView) == 0)
        ? _AgentDetailTab.details
        : _activeTab;

    if (_activeTab != activeTab) {
      _activeTab = activeTab;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tabs.index = _activeTab.index;
      });
    }

    // Fixed tab bar + scrolling content (Expanded) — so the Grants tab can host its own scrollable
    // list (ContextGrantsTab). The host gives this body a bounded height (split-view pane).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDetailTabs(
          controller: _tabs,
          tabs: [
            Tab(text: l10n.agentsTabDetails),
            Tab(text: l10n.agentsTabGrants),
            Tab(text: l10n.agentsTabLogs),
          ],
          disabledIndices: {
            if (lockedTabs) 1,
            if (lockedTabs || (permissions & Permissions.auditView) == 0) 2,
          },
          onSelected: (index) =>
              setState(() => _activeTab = _AgentDetailTab.values[index]),
        ),
        Expanded(
          child: switch (activeTab) {
            _AgentDetailTab.details => Stack(
              children: [
                Positioned.fill(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      AppSpacing.section,
                      AppSpacing.screenH,
                      canManage && widget.agent.isActive
                          ? AppFab.scrollClearance(context)
                          : AppSpacing.section,
                    ),
                    children: [
                      _DetailsCard(agent: widget.agent),
                      if (canManage) ...[
                        const SizedBox(height: AppSpacing.section),
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
                ),
                if (canManage && widget.agent.isActive)
                  Positioned(
                    right: AppSpacing.screenH,
                    bottom: AppFab.overlayInset(context),
                    child: AppFab(
                      onPressed: _onEdit,
                      tooltip: l10n.agentsEditTitle,
                      icon: Icons.edit_outlined,
                    ),
                  ),
              ],
            ),
            _AgentDetailTab.grants => Stack(
              children: [
                ContextGrantsTab(
                  key: ValueKey(_grantsRefresh),
                  agentId: widget.agent.agentId,
                  contentPadding: EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    AppSpacing.section,
                    AppSpacing.screenH,
                    canManage
                        ? AppFab.scrollClearance(context)
                        : AppSpacing.section,
                  ),
                  emptyTitle: l10n.agentGrantsEmptyTitle,
                  emptyHint: l10n.agentGrantsEmptyHint,
                ),
                if (canManage)
                  Positioned(
                    right: AppSpacing.screenH,
                    bottom: AppFab.overlayInset(context),
                    child: AppFab(
                      onPressed: _onAddGrant,
                      tooltip: l10n.grantAddGrant,
                    ),
                  ),
              ],
            ),
            _AgentDetailTab.logs => BlocProvider(
              key: ValueKey(widget.agent.agentId),
              create: (_) => AuditLogCubit(
                auditRepository: getIt<AuditRepository>(),
                presentationResolver: getIt<AuditPresentationResolver>(),
                scope: AuditLogScope.org,
                agentId: widget.agent.agentId,
              )..load(),
              child: const AuditLogContent(
                groups: AuditEventType.orgGroups,
                showVaultFilter: true,
                contentPadding: EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.section,
                  AppSpacing.screenH,
                  AppSpacing.section,
                ),
              ),
            ),
          },
        ),
      ],
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.agent});
  final Agent agent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: _MetadataList(agent: agent, l10n: l10n),
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
      _DetailRow(
        label: l10n.agentTypeLabel,
        value: agentTypeLabel(l10n, agent.type) ?? l10n.agentsTypeUnknown,
      ),
      if (agent.description?.isNotEmpty == true)
        _DetailRow(
          label: l10n.agentsEditDescription,
          value: agent.description!,
        ),
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
          if (i > 0)
            Divider(
              height: 1,
              color: AppColors.cardBorder(Theme.of(context).brightness),
            ),
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
      AgentStatus.active => CompactDangerZone(
        title: l10n.entryDangerZone,
        heading: l10n.agentsDeactivate,
        icon: Icons.block,
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
    final brightness = Theme.of(context).brightness;
    return ActionZone(
      title: title,
      semanticColor: AppColors.positiveAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            hint,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 12,
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
// ─────────────────────────────────────────────────────────────────────────
// Detail metadata
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
    return EntryFieldRow(
      icon: Icons.info_outline,
      value: value,
      isMasked: false,
      revealed: true,
      onToggleReveal: null,
      onCopy: null,
    ).labeled(label);
  }
}
