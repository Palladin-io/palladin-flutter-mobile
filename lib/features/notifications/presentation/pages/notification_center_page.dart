import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/widgets/primary_button_glow.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/crypto/vault_session_store.dart';
import '../../../../core/permissions.dart';
import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/jwt_claims.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../agents/presentation/bloc/agents_cubit.dart';
import '../../../agents/presentation/widgets/approve_agent_sheet.dart';
import '../../../agents/presentation/widgets/deactivate_agent_sheet.dart';
import '../../../approval/presentation/cubit/pending_grants_cubit.dart';
import '../../../approval/presentation/widgets/approve_grant_sheet.dart';
import '../../../approval/presentation/widgets/deny_grant_sheet.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../vault/presentation/cubit/vault_list_cubit.dart';
import '../../../vault/presentation/pages/entry_detail_page.dart';
import '../../data/services/notification_sharing_entry_resolver.dart';
import '../../domain/entities/entry_sharing_notification_target.dart';
import '../../domain/entities/inbox_notification.dart';
import '../cubit/notification_center_cubit.dart';
import '../widgets/notification_card.dart';
import '../widgets/notification_format.dart';

/// Log segments in the inbox toggle. Mirrors the web (All / To-do / History).
/// `all` = `todo` ∪ `history`. Grants is NOT a segment — it lives behind the
/// AppBar kebab as a separate full-screen page.
enum InboxSegment { all, todo, history }

/// Secondary inbox actions surfaced under the AppBar kebab. Mark-all-read stays
/// a primary AppBar action and is intentionally excluded.
enum _InboxMenuAction { grants, preferences }

/// The Notification Center / Inbox — the durable replacement for Approvals.
///
/// Two segments: **To-do** (open action-required items) and **History**
/// (everything resolved). Grant approve/deny reuses the existing
/// zero-knowledge sheets; other types deep-link to their owning surface.
class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key, this.focusId});

  /// Notification id to mark read on open (push deep-link `/inbox?focus=…`).
  final String? focusId;

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  late final NotificationCenterCubit _notifications =
      getIt<NotificationCenterCubit>();
  late final PendingGrantsCubit _pendingGrants = getIt<PendingGrantsCubit>();
  late final AgentsCubit _agents = getIt<AgentsCubit>();

  bool _isCurrent(AuthState auth) =>
      mounted &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      identical(context.read<AuthBloc>().state, auth);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthBloc>().state;
    await _configureUnlockedResolution();
    if (!_isCurrent(auth)) return;
    if (_notifications.state.status == NotificationCenterStatus.initial) {
      await _notifications.load();
    } else {
      await _notifications.refresh();
    }
    if (!_isCurrent(auth)) return;
    if (_canManageGrants()) _pendingGrants.refresh();
    final focusId = widget.focusId;
    if (focusId != null) await _notifications.markRead(focusId);
  }

  Future<void> _configureUnlockedResolution() async {
    final auth = context.read<AuthBloc>().state;
    final vaults = getIt<VaultListCubit>().state;
    if (auth is! AuthAuthenticated ||
        auth.isVaultLocked ||
        auth.privateKey == null ||
        vaults is! VaultListLoaded) {
      return;
    }
    final token = await getIt<SecureTokenStorage>().accessToken;
    final organizationId = token == null
        ? null
        : JwtClaims.organizationIdFrom(token);
    if (!_isCurrent(auth) ||
        organizationId == null ||
        !identical(getIt<VaultListCubit>().state, vaults) ||
        JwtClaims.decodePayload(token!)['sub'] != auth.userId) {
      return;
    }
    _notifications.configureUnlockedResolution(
      activeAccountId: auth.userId,
      activeOrganizationId: organizationId,
      activeVaults: vaults.vaults,
    );
  }

  bool _canManageGrants() {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated &&
        (auth.permissions & Permissions.grantManage) != 0;
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<NotificationCenterCubit>.value(value: _notifications),
        BlocProvider<PendingGrantsCubit>.value(value: _pendingGrants),
        BlocProvider<AgentsCubit>.value(value: _agents),
      ],
      child: const _NotificationCenterView(),
    );
  }
}

class _NotificationCenterView extends StatefulWidget {
  const _NotificationCenterView();

  @override
  State<_NotificationCenterView> createState() =>
      _NotificationCenterViewState();
}

class _NotificationCenterViewState extends State<_NotificationCenterView> {
  final TextEditingController _searchController = TextEditingController();
  int _sharingNavigationGeneration = 0;

  /// Active log segment. Grants is NOT a segment — it lives behind the AppBar
  /// kebab as a separate full-screen page.
  InboxSegment _segment = InboxSegment.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── actions ──────────────────────────────────────────────────────────

  Future<void> _onTap(InboxNotification item) async {
    final navigationGeneration = ++_sharingNavigationGeneration;
    if (item.type == 'entry_share_received') {
      await _openSharing(item, navigationGeneration);
      return;
    }
    final notifications = context.read<NotificationCenterCubit>();
    await notifications.markRead(item.id);
    if (!mounted) return;
    if (item.isOpenAction) {
      if (item.type == 'grant_pending') {
        await _approveGrant(item);
        return;
      }
      if (item.type == 'agent_pending') {
        await _approveAgent(item);
        return;
      }
    }
    _deepLink(item);
  }

  Future<void> _openSharing(InboxNotification item, int generation) async {
    final target = entrySharingNotificationTarget(item);
    final auth = context.read<AuthBloc>();
    final owner = auth.state;
    final vaults = getIt<VaultListCubit>();
    final initialVaults = vaults.state;
    if (target == null ||
        owner is! AuthAuthenticated ||
        owner.isVaultLocked ||
        owner.privateKey == null ||
        !owner.emailVerified ||
        (owner.permissions & Permissions.vaultManage) == 0 ||
        initialVaults is! VaultListLoaded ||
        !initialVaults.vaults.any((vault) => vault.id == target.vaultId)) {
      _sharingUnavailable();
      return;
    }
    final keys = getIt<VaultSessionStore>();
    final keyGeneration = keys.memberKeySessionGeneration;
    final inbox = context.read<NotificationCenterCubit>();
    final inboxGeneration = inbox.presentationGeneration;
    bool isCurrent() =>
        mounted &&
        generation == _sharingNavigationGeneration &&
        identical(auth.state, owner) &&
        identical(vaults.state, initialVaults) &&
        keys.memberKeySessionGeneration == keyGeneration &&
        inbox.presentationGeneration == inboxGeneration &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) &&
        (ModalRoute.of(context)?.isCurrent ?? false);
    if (!isCurrent()) return;
    await inbox.markRead(item.id);
    if (!isCurrent()) return;
    final entry = await getIt<NotificationSharingEntryResolver>().resolve(
      target: target,
      principalId: owner.userId,
      memberPrivateKey: owner.privateKey!,
      isCurrent: isCurrent,
    );
    if (!isCurrent()) return;
    if (entry == null) {
      _sharingUnavailable();
      return;
    }
    if (!mounted) return;
    await EntryDetailPage.push(context, entry: entry, showSharing: true);
  }

  void _sharingUnavailable() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.inboxSharingUnavailable),
      ),
    );
  }

  // ── agent flows ────────────────────────────────────────────────────────

  /// Approve a pending agent — opens the existing activation sheet, then runs
  /// the agent approval mutation and marks the notification read.
  Future<void> _approveAgent(InboxNotification item) async {
    final agentId = item.agentId;
    if (agentId == null) return;
    final agents = context.read<AgentsCubit>();
    final notifications = context.read<NotificationCenterCubit>();
    final result = await ApproveAgentSheet.show(
      context,
      initialName: item.metadata['agentName'] as String?,
      initialType: item.metadata['agentType'] as String?,
    );
    if (result == null) return;
    await agents.approveAgent(
      agentId,
      name: result.name,
      type: result.type,
      iconKey: result.iconKey,
    );
    // Collapse the To-do card immediately on success so it does not linger
    // while the (slower) inbox refresh catches up. _runMutation reports
    // failure via mutationError rather than throwing.
    if (agents.state.mutationError == null) {
      notifications.markResolvedLocally(item.id);
    }
    await notifications.refresh();
  }

  /// Deny a pending agent = deactivate it (no separate reject endpoint).
  Future<void> _denyAgent(InboxNotification item) async {
    final agentId = item.agentId;
    if (agentId == null) return;
    final agents = context.read<AgentsCubit>();
    final notifications = context.read<NotificationCenterCubit>();
    final agentName =
        (item.metadata['agentName'] as String?) ?? item.agentId ?? '';
    final confirmed = await DeactivateAgentSheet.show(context, agentName);
    if (!confirmed) return;
    await agents.deactivateAgent(agentId);
    // Only collapse + mark read when the deny actually succeeded — a failed
    // mutation must leave the card actionable (and unread) so the user retries.
    if (agents.state.mutationError == null) {
      notifications.markResolvedLocally(item.id);
      await notifications.markRead(item.id);
    }
    await notifications.refresh();
  }

  /// Resolves the pending grant from the source feed and shows the existing
  /// zero-knowledge approval sheet. The Inbox event can arrive before the
  /// pending-grants singleton observed the request, so we refresh first.
  Future<void> _approveGrant(InboxNotification item) =>
      _runGrantSheet(item, approve: true);

  Future<void> _denyGrant(InboxNotification item) async {
    await context.read<NotificationCenterCubit>().markRead(item.id);
    if (!mounted) return;
    await _runGrantSheet(item, approve: false);
  }

  Future<void> _runGrantSheet(
    InboxNotification item, {
    required bool approve,
  }) async {
    final pending = context.read<PendingGrantsCubit>();
    // The Inbox event can arrive before the pending-grants singleton observed
    // the new request, so refresh the source feed first, then resolve it.
    await pending.refresh(ensureFresh: true);
    if (!context.mounted) return;
    _showGrantSheet(item, approve: approve);
  }

  /// Synchronous continuation of [_runGrantSheet]: resolves the pending grant
  /// from the (already refreshed) source feed and shows the existing
  /// zero-knowledge sheet. Kept sync up to the sheet call so the BuildContext
  /// is used without crossing an async gap.
  void _showGrantSheet(InboxNotification item, {required bool approve}) {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final notifications = context.read<NotificationCenterCubit>();
    final pending = context.read<PendingGrantsCubit>();

    final grantId = item.grantId;
    PendingGrant? grant;
    for (final candidate in pending.state.grants) {
      if (candidate.grantId == grantId) {
        grant = candidate;
        break;
      }
    }
    if (grant == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.inboxActionGone)));
      unawaited(notifications.refresh());
      return;
    }

    final resolved = grant;
    final future = approve
        ? ApproveGrantSheet.show(context, resolved)
        : DenyGrantSheet.show(context, resolved);
    future.then((handled) {
      if (handled != true) return;
      pending.removeGrant(resolved.grantId);
      // Collapse the inbox card immediately so the approved/denied request
      // does not hang in To-do until the server refresh returns.
      notifications.markResolvedLocally(item.id);
      notifications.refresh();
    });
  }

  /// Uses only allowlisted Inbox types and structural ids, never a supplied URL.
  void _deepLink(InboxNotification item) {
    final target = notificationDeepLink(item);
    if (target != null) context.go(target);
  }

  /// Secondary footer action (Deny) for the two action-required pending types.
  Future<void> _onSecondary(InboxNotification item) async {
    if (item.type == 'grant_pending') {
      await _denyGrant(item);
      return;
    }
    if (item.type == 'agent_pending') {
      await _denyAgent(item);
    }
  }

  // ── build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return AppScreen.titled(
      title: l10n.inboxTitle,
      // Suppress any FAB leaking from a page we were navigated over.
      floatingActionButton: const FabRegistrar(fab: null),
      // Mark-all-read stays a primary action in the title row; the kebab
      // overflow (Grants / Preferences) lives at the end of the segment row.
      actions: [
        BlocBuilder<NotificationCenterCubit, NotificationCenterState>(
          buildWhen: (p, c) =>
              p.unreadCount != c.unreadCount ||
              p.isMarkingAllRead != c.isMarkingAllRead,
          builder: (context, state) {
            final enabled = state.unreadCount > 0 && !state.isMarkingAllRead;
            return TextButton.icon(
              onPressed: enabled
                  ? () => context.read<NotificationCenterCubit>().markAllRead()
                  : null,
              icon: Icon(
                Icons.done_all,
                size: 16,
                color: enabled
                    ? AppColors.onSurfaceMuted(brightness)
                    : AppColors.onSurfaceSubtle(brightness),
              ),
              label: Text(l10n.inboxMarkAllRead),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurfaceMuted(brightness),
                disabledForegroundColor: AppColors.onSurfaceSubtle(brightness),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                visualDensity: VisualDensity.compact,
              ),
            );
          },
        ),
      ],
      // Header → segments gap is owned by the titled header. Only the title is
      // pinned; the segment row and search scroll together with the feed
      // (canonical Vaults pattern) so an overscroll never reveals a background
      // strip between a pinned control and a separate scroll area.
      body: _Feed(
        segment: _segment,
        query: _searchController.text,
        onTapItem: _onTap,
        onSecondary: _onSecondary,
        header: _InboxControls(
          segment: _segment,
          searchController: _searchController,
          onSegmentChanged: (s) => setState(() => _segment = s),
          onSearchChanged: () => setState(() {}),
          onMenuSelected: (action) => switch (action) {
            _InboxMenuAction.grants => context.push('/inbox/grants'),
            _InboxMenuAction.preferences => context.push('/inbox/preferences'),
          },
        ),
      ),
    );
  }
}

/// The scrolling header that sits above the feed: the segment toggle + overflow
/// row, then the search field. Both scroll with the feed — see [_Feed].
class _InboxControls extends StatelessWidget {
  const _InboxControls({
    required this.segment,
    required this.searchController,
    required this.onSegmentChanged,
    required this.onSearchChanged,
    required this.onMenuSelected,
  });

  final InboxSegment segment;
  final TextEditingController searchController;
  final ValueChanged<InboxSegment> onSegmentChanged;
  final VoidCallback onSearchChanged;
  final ValueChanged<_InboxMenuAction> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // segments → search: fieldGap
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.fieldGap,
          ),
          child: Row(
            children: [
              Expanded(
                child:
                    BlocBuilder<
                      NotificationCenterCubit,
                      NotificationCenterState
                    >(
                      buildWhen: (p, c) =>
                          p.pendingActionCount != c.pendingActionCount,
                      builder: (context, state) => _SegmentToggle(
                        segment: segment,
                        todoCount: state.pendingActionCount,
                        onChanged: onSegmentChanged,
                      ),
                    ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _SegmentOverflowButton(onSelected: onMenuSelected),
            ],
          ),
        ),
        // Search applies to all three log segments. The Grants list is a
        // separate page (kebab) with its own UI.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: AppSearchField(
            controller: searchController,
            hint: l10n.inboxSearchHint,
            onChanged: (_) => onSearchChanged(),
          ),
        ),
        // search → first result / empty-state: fieldGap
        const SizedBox(height: AppSpacing.fieldGap),
      ],
    );
  }
}

// ── feed ───────────────────────────────────────────────────────────────

class _Feed extends StatelessWidget {
  const _Feed({
    required this.segment,
    required this.query,
    required this.onTapItem,
    required this.onSecondary,
    required this.header,
  });

  final InboxSegment segment;
  final String query;
  final Future<void> Function(InboxNotification) onTapItem;
  final Future<void> Function(InboxNotification) onSecondary;

  /// Scrolling header (segment row + search) rendered as the first sliver so it
  /// scrolls with the feed instead of being pinned above a separate scroll
  /// area.
  final Widget header;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      color: AppColors.brandRed,
      backgroundColor: AppColors.cardSurface(Theme.of(context).brightness),
      onRefresh: () => context.read<NotificationCenterCubit>().refresh(),
      child: BlocBuilder<NotificationCenterCubit, NotificationCenterState>(
        builder: (context, state) {
          final contentSlivers = switch (state.status) {
            NotificationCenterStatus.initial ||
            NotificationCenterStatus.loading => const [_SkeletonSliver()],
            NotificationCenterStatus.error => [
              _ErrorSliver(
                message: notificationErrorMessage(l10n, state.error!),
                onRetry: () => context.read<NotificationCenterCubit>().load(),
              ),
            ],
            NotificationCenterStatus.loaded => _listSlivers(
              context,
              items: _filter(state.items),
              isLoadingMore: state.isLoadingMore,
            ),
          };
          // Pagination: a scroll that nears the end asks the cubit for the next
          // page. Wrapping the whole scroll view keeps loadMore working with
          // the header in the same scrollable.
          return NotificationListener<ScrollEndNotification>(
            onNotification: (notification) {
              if (state.status == NotificationCenterStatus.loaded &&
                  notification.metrics.extentAfter < 160) {
                context.read<NotificationCenterCubit>().loadMore();
              }
              return false;
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: header),
                ...contentSlivers,
              ],
            ),
          );
        },
      ),
    );
  }

  List<InboxNotification> _filter(List<InboxNotification> items) {
    final q = query.trim().toLowerCase();
    return items
        .where((item) {
          // Collapse resolved pending action items — the backend zips them up
          // once approved/denied, so never show a resolved To-do card.
          if (item.isCollapsedPending) return false;
          // All = To-do ∪ History (every non-collapsed item); To-do = open
          // actions only; History = everything resolved/informational.
          final segmentMatches = switch (segment) {
            InboxSegment.all => true,
            InboxSegment.todo => item.isOpenAction,
            InboxSegment.history => !item.isOpenAction,
          };
          if (!segmentMatches) return false;
          if (q.isEmpty) return true;
          final haystack = [
            item.type,
            ...item.metadata.values.whereType<String>(),
          ].join(' ').toLowerCase();
          return haystack.contains(q);
        })
        .toList(growable: false);
  }

  /// Builds the loaded-state slivers: either the per-segment empty card or the
  /// paginated list of notification tiles (with a trailing spinner while the
  /// next page loads). Rendered below the (scrolling) header in [build].
  List<Widget> _listSlivers(
    BuildContext context, {
    required List<InboxNotification> items,
    required bool isLoadingMore,
  }) {
    final l10n = AppLocalizations.of(context)!;
    if (items.isEmpty) {
      final (icon, title, hint) = switch (segment) {
        InboxSegment.todo => (
          Icons.task_alt,
          l10n.inboxTodoEmpty,
          l10n.inboxTodoEmptyHint,
        ),
        InboxSegment.history => (
          Icons.history,
          l10n.inboxUpdatesEmpty,
          l10n.inboxUpdatesEmptyHint,
        ),
        InboxSegment.all => (
          Icons.inbox_outlined,
          l10n.inboxAllEmpty,
          l10n.inboxAllEmptyHint,
        ),
      };
      // search → empty-state gap (fieldGap) is owned by the header above.
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.screenBottom,
          ),
          sliver: SliverList.list(
            children: [_EmptyCard(icon: icon, title: title, hint: hint)],
          ),
        ),
      ];
    }
    // No section header: each segment renders a single section (To-do or
    // History), and we never label the first rendered section. The segment
    // toggle already names the active list. search → first result gap
    // (fieldGap) is owned by the header above.
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          0,
          AppSpacing.screenH,
          AppSpacing.listBottom,
        ),
        sliver: SliverList.separated(
          itemCount: items.length + (isLoadingMore ? 1 : 0),
          separatorBuilder: (_, _) =>
              const SizedBox(height: AppSpacing.cardGap),
          itemBuilder: (context, index) {
            if (index == items.length) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.fieldGap),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.brandRed),
                ),
              );
            }
            return _NotificationItemTile(
              item: items[index],
              onTap: () => onTapItem(items[index]),
              onSecondary: () => onSecondary(items[index]),
            );
          },
        ),
      ),
    ];
  }
}

/// Maps a notification to the right [NotificationCard] footer wiring.
class _NotificationItemTile extends StatefulWidget {
  const _NotificationItemTile({
    required this.item,
    required this.onTap,
    required this.onSecondary,
  });

  final InboxNotification item;
  final Future<void> Function() onTap;
  final Future<void> Function() onSecondary;

  @override
  State<_NotificationItemTile> createState() => _NotificationItemTileState();
}

class _NotificationItemTileState extends State<_NotificationItemTile> {
  /// True while a primary/secondary action triggered from this card is in
  /// flight. Guards against a second tap re-running the mutation while the
  /// list refresh is still catching up — which previously let a slow
  /// approve be submitted twice (double-activation).
  bool _busy = false;

  /// Runs [action] under the re-entrancy guard, disabling the card's actions
  /// until it completes. For agent approve/deny this spans the full mutation +
  /// list refresh; for grant approve/deny the guard releases once the grant
  /// sheet is shown (the crypto mutation then runs in the sheet's own flow),
  /// which still blocks a double-tap from opening two sheets.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // Mark-on-view: a tile that mounts has scrolled into view, so mark it read
    // (drops the unread badge after scrolling/opening). Scoped to the mount
    // lifecycle — not re-fired on every rebuild — and scheduled post-frame so
    // we never mutate cubit state during build; idempotent + de-duped in the
    // cubit. Does NOT affect the To-do/action counter.
    if (!widget.item.isRead) {
      final cubit = context.read<NotificationCenterCubit>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        cubit.markReadOnView(widget.item.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final item = widget.item;
    void onTap() => _run(widget.onTap);
    void onSecondary() => _run(widget.onSecondary);

    // Action-required PENDING grant/agent: the only cards with inline
    // mutating actions (Approve / Deny). Every other card is an immutable log
    // entry with at most a non-mutating "View" deep-link.
    if (item.isOpenAction &&
        (item.type == 'grant_pending' || item.type == 'agent_pending')) {
      return NotificationCard(
        item: item,
        onTap: onTap,
        onSecondary: onSecondary,
        secondaryLabel: l10n.approvalDeny,
        onPrimary: onTap,
        primaryLabel: item.type == 'agent_pending'
            ? l10n.inboxAcceptAction
            : l10n.approvalApprove,
        isBusy: _busy,
      );
    }

    // Everything else (resolved, informational, or unknown future types): a
    // single contextual "View" link (View Agent / View Access / View Entry) to
    // the owning surface — rendered only when a deep-link target exists,
    // otherwise the card has no footer.
    final route = notificationDeepLink(item);
    final target = notificationViewTarget(item);
    final hasView =
        target != null &&
        (route != null || entrySharingNotificationTarget(item) != null);
    return NotificationCard(
      item: item,
      onTap: onTap,
      onView: hasView ? onTap : null,
      viewLabel: hasView ? notificationViewLabel(l10n, target) : null,
      isBusy: _busy,
    );
  }
}

// ── kebab menu ───────────────────────────────────────────────────────────

/// Overflow ("more") button at the end of the segment row — the pattern for a
/// tab strip with extra destinations (Grants / Preferences). Matches the
/// segment track's height ([AppSpacing.controlHeight]) and styling so it lines
/// up flush with All / To-do / History.
class _SegmentOverflowButton extends StatelessWidget {
  const _SegmentOverflowButton({required this.onSelected});

  final ValueChanged<_InboxMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      height: AppSpacing.controlHeight,
      width: AppSpacing.controlHeight,
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: PopupMenuButton<_InboxMenuAction>(
        tooltip: l10n.inboxMoreActions,
        padding: EdgeInsets.zero,
        icon: Icon(
          Icons.more_horiz,
          size: 20,
          color: AppColors.iconDefault(brightness),
        ),
        color: AppColors.cardSurface(brightness),
        onSelected: onSelected,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _InboxMenuAction.grants,
            child: _MenuRow(
              icon: Icons.vpn_key_outlined,
              label: l10n.inboxGrantsMenu,
            ),
          ),
          PopupMenuItem(
            value: _InboxMenuAction.preferences,
            child: _MenuRow(icon: Icons.tune, label: l10n.inboxPreferencesMenu),
          ),
        ],
      ),
    );
  }
}

/// Icon + label row for a kebab [PopupMenuItem].
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.iconDefault(brightness)),
        const SizedBox(width: AppSpacing.fieldGap),
        Text(
          label,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

// ── segmented toggle ─────────────────────────────────────────────────────

class _SegmentToggle extends StatelessWidget {
  const _SegmentToggle({
    required this.segment,
    required this.todoCount,
    required this.onChanged,
  });

  final InboxSegment segment;
  final int todoCount;
  final ValueChanged<InboxSegment> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      // Matches the search bar height so every under-title control lines up.
      height: AppSpacing.controlHeight,
      // Segmented-control track inset — a fixed component dimension, not a
      // layout gap, so it stays raw (no semantic token of this size).
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SegmentButton(
            label: l10n.inboxSegAll,
            selected: segment == InboxSegment.all,
            onTap: () => onChanged(InboxSegment.all),
          ),
          _SegmentButton(
            label: l10n.inboxTodo,
            badge: todoCount > 0 ? todoCount : null,
            selected: segment == InboxSegment.todo,
            onTap: () => onChanged(InboxSegment.todo),
          ),
          _SegmentButton(
            label: l10n.inboxHistory,
            selected: segment == InboxSegment.history,
            onTap: () => onChanged(InboxSegment.history),
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
      child: PrimaryButtonGlow(
        enabled: selected,
        radius: 8,
        child: Material(
          color: selected ? AppColors.brandRed : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            // Cell is stretched to the track height — center the label so the
            // selected pill fills the full height with the text centred.
            child: Center(
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
                    const SizedBox(width: AppSpacing.chipGap),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.onBrandRed.withValues(alpha: 0.25)
                            : AppColors.brandRed,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
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
      ),
    );
  }
}

// ── shared sub-widgets ───────────────────────────────────────────────────

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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: 28,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.onSurfaceSubtle(brightness)),
          const SizedBox(height: AppSpacing.fieldGap),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
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

class _SkeletonSliver extends StatelessWidget {
  const _SkeletonSliver();

  @override
  Widget build(BuildContext context) {
    // search → first skeleton gap (fieldGap) is owned by the header above.
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      sliver: SliverList.list(
        children: List.generate(
          4,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
            child: SkeletonBox(
              height: 112,
              delay: Duration(milliseconds: i * 80),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorSliver extends StatelessWidget {
  const _ErrorSliver({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    // search → error card gap (fieldGap) is owned by the header above.
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      sliver: SliverList.list(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
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
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brandRed,
                  ),
                  child: Text(l10n.approvalRetry),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
