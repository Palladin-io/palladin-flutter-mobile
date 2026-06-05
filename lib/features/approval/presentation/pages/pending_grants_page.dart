import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../grants/domain/entities/grant.dart';
import '../../../grants/presentation/cubit/org_grants_cubit.dart';
import '../../../grants/presentation/widgets/grant_format.dart';
import '../../../grants/presentation/widgets/org_grant_card.dart';
import '../../../grants/presentation/widgets/revoke_grant_sheet.dart';
import '../cubit/pending_grants_cubit.dart';
import '../widgets/approval_format.dart';
import '../widgets/approve_grant_sheet.dart';
import '../widgets/deny_grant_sheet.dart';
import '../widgets/regrant_sheet.dart';

/// The Approvals screen — the mobile counterpart of the web Approvals view.
///
/// Two segments mirror the web split-view: **Pending** (the actionable
/// approve/deny inbox, left on web) and **History** (every other org-wide
/// grant with status pills, search + status filter, and inline revoke — the
/// web `OrgGrantsPanel`, right on web). Single-column with a segmented toggle
/// is the mobile-native equivalent of the two-pane desktop layout.
class PendingGrantsPage extends StatefulWidget {
  const PendingGrantsPage({super.key});

  @override
  State<PendingGrantsPage> createState() => _PendingGrantsPageState();
}

class _PendingGrantsPageState extends State<PendingGrantsPage> {
  // Singleton (drives the nav badge too) — provided by value so this page's
  // dispose won't close it. Held as a state field so we don't pull it from
  // getIt on every rebuild (and so the load/refresh side-effect fires once).
  late final PendingGrantsCubit _pending = getIt<PendingGrantsCubit>();

  @override
  void initState() {
    super.initState();
    // Show a skeleton only on the very first load; otherwise refresh quietly
    // so an already-populated list never flickers.
    if (_pending.state.status == PendingGrantsStatus.initial) {
      _pending.load();
    } else {
      _pending.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<PendingGrantsCubit>.value(value: _pending),
        BlocProvider<OrgGrantsCubit>(
          create: (_) => getIt<OrgGrantsCubit>()..load(),
        ),
      ],
      child: const _ApprovalsView(),
    );
  }
}

class _ApprovalsView extends StatefulWidget {
  const _ApprovalsView();

  @override
  State<_ApprovalsView> createState() => _ApprovalsViewState();
}

class _ApprovalsViewState extends State<_ApprovalsView> {
  int _segment = 0; // 0 = pending, 1 = history
  bool _filtersOpen = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _approve(BuildContext context, PendingGrant grant) =>
      _act(context, grant, ApproveGrantSheet.show(context, grant));

  Future<void> _deny(BuildContext context, PendingGrant grant) =>
      _act(context, grant, DenyGrantSheet.show(context, grant));

  /// Shared post-action handling: when the sheet reports the grant was handled
  /// (approved/denied), drop it from the inbox and refresh the history feed.
  Future<void> _act(
    BuildContext context,
    PendingGrant grant,
    Future<bool?> sheet,
  ) async {
    final cubit = context.read<PendingGrantsCubit>();
    final orgCubit = context.read<OrgGrantsCubit>();
    final handled = await sheet;
    if (handled == true) {
      cubit.removeGrant(grant.grantId);
      orgCubit.load();
    }
  }

  Future<void> _revoke(BuildContext context, Grant grant) async {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<OrgGrantsCubit>();
    final result = await RevokeGrantSheet.show(
      context,
      grant.agentName?.trim().isNotEmpty == true
          ? grant.agentName!.trim()
          : l10n.grantUnnamedAgent,
    );
    if (result == null) return;
    await cubit.revokeGrant(grant.vaultId, grant.id, reason: result.reason);
  }

  Future<void> _regrant(BuildContext context, Grant grant) async {
    final cubit = context.read<OrgGrantsCubit>();
    final done = await RegrantSheet.show(context, grant);
    // A new active grant supersedes the terminal one — reload so the feed and
    // the capability flags reflect it.
    if (done == true) cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient(brightness),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: false,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          titleSpacing: 20,
          iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
          title: Text(
            l10n.approvalInboxTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: BlocBuilder<PendingGrantsCubit, PendingGrantsState>(
                  builder: (context, state) => _SegmentToggle(
                    segment: _segment,
                    pendingCount: state.grants.length,
                    onChanged: (i) => setState(() => _segment = i),
                  ),
                ),
              ),
              Expanded(
                child: _segment == 0
                    ? _PendingSegment(
                        onApprove: (g) => _approve(context, g),
                        onDeny: (g) => _deny(context, g),
                      )
                    : _HistorySegment(
                        searchController: _searchController,
                        filtersOpen: _filtersOpen,
                        onToggleFilters: () =>
                            setState(() => _filtersOpen = !_filtersOpen),
                        onRevoke: (g) => _revoke(context, g),
                        onRegrant: (g) => _regrant(context, g),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── segmented toggle ───────────────────────────────────────────────────────

class _SegmentToggle extends StatelessWidget {
  const _SegmentToggle({
    required this.segment,
    required this.pendingCount,
    required this.onChanged,
  });

  final int segment;
  final int pendingCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: l10n.approvalSegmentPending,
            badge: pendingCount > 0 ? pendingCount : null,
            selected: segment == 0,
            onTap: () => onChanged(0),
          ),
          _SegmentButton(
            label: l10n.approvalSegmentHistory,
            selected: segment == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fg = selected
        ? AppColors.onBrandRed
        : AppColors.onSurfaceMuted(brightness);
    return Expanded(
      child: Material(
        color: selected ? AppColors.brandRed : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.onBrandRed.withValues(alpha: 0.25)
                          : AppColors.brandRed,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        color: AppColors.onBrandRed,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── pending segment ────────────────────────────────────────────────────────

class _PendingSegment extends StatelessWidget {
  const _PendingSegment({required this.onApprove, required this.onDeny});

  final ValueChanged<PendingGrant> onApprove;
  final ValueChanged<PendingGrant> onDeny;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      color: AppColors.brandRed,
      backgroundColor: AppColors.cardSurface(Theme.of(context).brightness),
      onRefresh: () => context.read<PendingGrantsCubit>().load(),
      child: BlocBuilder<PendingGrantsCubit, PendingGrantsState>(
        builder: (context, state) => switch (state.status) {
          PendingGrantsStatus.initial ||
          PendingGrantsStatus.loading =>
            const _Skeleton(),
          PendingGrantsStatus.error => _ErrorView(
              message: approvalErrorMessage(l10n, state.error!),
              onRetry: () => context.read<PendingGrantsCubit>().load(),
            ),
          PendingGrantsStatus.loaded => _PendingList(
              grants: state.grants,
              onApprove: onApprove,
              onDeny: onDeny,
            ),
        },
      ),
    );
  }
}

class _PendingList extends StatelessWidget {
  const _PendingList({
    required this.grants,
    required this.onApprove,
    required this.onDeny,
  });

  final List<PendingGrant> grants;
  final ValueChanged<PendingGrant> onApprove;
  final ValueChanged<PendingGrant> onDeny;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (grants.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _EmptyCard(
            icon: Icons.inbox_outlined,
            title: l10n.approvalInboxEmpty,
            hint: l10n.approvalInboxEmptyHint,
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      itemCount: grants.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _PendingCard(
        grant: grants[i],
        onApprove: () => onApprove(grants[i]),
        onDeny: () => onDeny(grants[i]),
      ),
    );
  }
}

/// Pending-approval card — the mobile counterpart of the web `PendingGrantCard`:
/// agent identity row ("requests access"), aligned Entry/Requested/Reason rows,
/// and a Deny / Approve footer. All three (card tap + both buttons) open the
/// approve/deny screen, which performs the zero-knowledge approval envelope.
class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.grant,
    required this.onApprove,
    required this.onDeny,
  });

  final PendingGrant grant;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final hasReason = grant.reason != null && grant.reason!.trim().isNotEmpty;

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
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onApprove,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.positiveAccent.withValues(alpha: 0.12),
                        ),
                        child: const Icon(
                          Icons.smart_toy,
                          size: 16,
                          color: AppColors.positiveAccent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              pendingAgentDisplayName(l10n, grant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.onSurface(brightness),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.approvalPendingRequestsAccess,
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
            ),
            Divider(height: 1, thickness: 1, color: AppColors.cardBorder(brightness)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GrantDetailRow(
                    label: l10n.orgGrantRowEntry,
                    value: pendingEntryLabel(l10n, grant),
                  ),
                  const SizedBox(height: 8),
                  GrantDetailRow(
                    label: l10n.approvalPendingRowRequested,
                    value: grantRelativeTime(l10n, grant.createdAt),
                  ),
                  if (hasReason) ...[
                    const SizedBox(height: 8),
                    GrantDetailRow(
                      label: l10n.orgGrantRowReason,
                      value: grant.reason!.trim(),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardFooterOverlay(brightness),
                border: Border(
                  top: BorderSide(color: AppColors.cardBorder(brightness)),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: OutlinedButton(
                        onPressed: onDeny,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.onSurfaceMuted(brightness),
                          side: BorderSide(color: AppColors.cardBorder(brightness)),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          l10n.approvalDeny,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: FilledButton(
                        onPressed: onApprove,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.positiveAccent,
                          foregroundColor: AppColors.onBrandRed,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          l10n.approvalApprove,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── history segment ────────────────────────────────────────────────────────

/// Statuses offered in the history filter — pending is excluded (it lives in
/// the other segment). Order mirrors the web summary order.
const _historyStatuses = <GrantStatus>[
  GrantStatus.active,
  GrantStatus.expired,
  GrantStatus.consumed,
  GrantStatus.denied,
  GrantStatus.revoked,
];

class _HistorySegment extends StatelessWidget {
  const _HistorySegment({
    required this.searchController,
    required this.filtersOpen,
    required this.onToggleFilters,
    required this.onRevoke,
    required this.onRegrant,
  });

  final TextEditingController searchController;
  final bool filtersOpen;
  final VoidCallback onToggleFilters;
  final ValueChanged<Grant> onRevoke;
  final ValueChanged<Grant> onRegrant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocListener<OrgGrantsCubit, OrgGrantsState>(
      listenWhen: (p, c) => p.mutationError != c.mutationError,
      listener: (context, state) {
        if (state.mutationError == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(grantsErrorMessage(l10n, state.mutationError!))),
        );
        context.read<OrgGrantsCubit>().acknowledgeMutationError();
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: AppSearchField(
              controller: searchController,
              hint: l10n.approvalHistorySearchHint,
              filterActive: filtersOpen,
              onChanged: (q) => context.read<OrgGrantsCubit>().search(q),
              onToggleFilter: onToggleFilters,
            ),
          ),
          if (filtersOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: BlocBuilder<OrgGrantsCubit, OrgGrantsState>(
                buildWhen: (p, c) => p.statusFilter != c.statusFilter,
                builder: (context, state) => _StatusFilterChips(
                  selected: state.statusFilter,
                  onToggle: (s) =>
                      context.read<OrgGrantsCubit>().toggleStatus(s),
                  onClear: () =>
                      context.read<OrgGrantsCubit>().clearStatusFilter(),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.brandRed,
              backgroundColor:
                  AppColors.cardSurface(Theme.of(context).brightness),
              onRefresh: () => context.read<OrgGrantsCubit>().load(),
              child: BlocBuilder<OrgGrantsCubit, OrgGrantsState>(
                builder: (context, state) => switch (state.status) {
                  OrgGrantsStatus.initial ||
                  OrgGrantsStatus.loading =>
                    const _Skeleton(),
                  OrgGrantsStatus.error => _ErrorView(
                      message: grantsErrorMessage(l10n, state.error!),
                      onRetry: () => context.read<OrgGrantsCubit>().load(),
                    ),
                  OrgGrantsStatus.loaded => _HistoryList(
                      grants: state.filtered,
                      revokingGrantId: state.revokingGrantId,
                      onRevoke: onRevoke,
                      onRegrant: onRegrant,
                    ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterChips extends StatelessWidget {
  const _StatusFilterChips({
    required this.selected,
    required this.onToggle,
    required this.onClear,
  });

  final Set<GrantStatus> selected;
  final ValueChanged<GrantStatus> onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final status in _historyStatuses)
          _FilterChip(
            label: grantStatusLabel(l10n, status),
            color: grantStatusColor(status),
            selected: selected.contains(status),
            onTap: () => onToggle(status),
          ),
        if (selected.isNotEmpty)
          _FilterChip(
            label: l10n.approvalHistoryFilterClear,
            color: AppColors.textTertiary,
            selected: false,
            onTap: onClear,
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Material(
      color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? color : AppColors.cardBorder(brightness),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? color : AppColors.onSurfaceMuted(brightness),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.grants,
    required this.revokingGrantId,
    required this.onRevoke,
    required this.onRegrant,
  });

  final List<Grant> grants;
  final String? revokingGrantId;
  final ValueChanged<Grant> onRevoke;
  final ValueChanged<Grant> onRegrant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (grants.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          _EmptyCard(
            icon: Icons.history,
            title: l10n.approvalHistoryEmpty,
            hint: l10n.approvalHistoryEmptyHint,
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      itemCount: grants.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => OrgGrantCard(
        grant: grants[i],
        isRevoking: revokingGrantId == grants[i].id,
        onRevoke: () => onRevoke(grants[i]),
        onRegrant: () => onRegrant(grants[i]),
      ),
    );
  }
}

// ── shared sub-widgets ─────────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.onSurfaceSubtle(brightness)),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: List.generate(
        4,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SkeletonBox(height: 84, delay: Duration(milliseconds: i * 80)),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder(brightness)),
          ),
          child: Column(
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealAccent,
                ),
                child: Text(l10n.approvalRetry),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
