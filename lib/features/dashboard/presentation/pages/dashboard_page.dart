import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../agents/presentation/widgets/approve_agent_sheet.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../vault/domain/entities/entry_entity.dart';
import '../../../vault/presentation/pages/entry_detail_page.dart';
import '../../../vault/presentation/widgets/vault_visuals.dart';
import '../../domain/entities/search_result_entity.dart';
import '../cubit/dashboard_cubit.dart';
import '../cubit/search_cubit.dart';
import '../cubit/search_state.dart';
import '../widgets/onboarding_checklist.dart';
import '../widgets/unknown_agent_card.dart';

/// Home tab — replaces the post-unlock placeholder.
///
/// Shows one of three content states below a static greeting + search:
/// the onboarding checklist, an unknown-agent prompt, or the normal
/// (empty) dashboard. The [DashboardCubit] is a shell-lifetime singleton;
/// [load] runs on each mount to refresh after the user returns to the tab.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final DashboardCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = getIt<DashboardCubit>()..load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DashboardCubit>.value(
      value: _cubit,
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatefulWidget {
  const _DashboardView();

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  final TextEditingController _searchController = TextEditingController();
  late final SearchCubit _searchCubit = getIt<SearchCubit>();

  @override
  void dispose() {
    _searchController.dispose();
    _searchCubit.close();
    super.dispose();
  }

  /// Fires analytics, navigates to the tapped result, then clears the
  /// search field so the dashboard content is visible on return.
  void _onSearchResultTap(BuildContext context, SearchResultEntity result) {
    _searchCubit.selectResult(result);
    switch (result.type) {
      case SearchResultType.agent:
        context.go(AppRoutes.agentDetail(result.id));
      case SearchResultType.vault:
        context.go(AppRoutes.vaultDetail(result.id));
      case SearchResultType.entry:
        _openEntryDetail(context, result);
    }
    _searchController.clear();
    _searchCubit.reset();
  }

  /// Deep-links into the entry detail screen for an `entry` search hit.
  ///
  /// The search projection carries only [SearchResultEntity.id],
  /// [SearchResultEntity.vaultId], [SearchResultEntity.name] and an optional
  /// icon — enough to bootstrap [EntryDetailPage], which then fetches and
  /// decrypts the full entry (real type + timestamps) on open. The bootstrap
  /// [EntryEntity]'s `type`/`createdAt`/`updatedAt` are placeholders replaced
  /// by the revealed entity, so they are never persisted.
  ///
  /// `vaultId` is entry-only and defensively nullable; if the backend omits
  /// it we fall back to the vault list so the tap is never a dead end.
  void _openEntryDetail(BuildContext context, SearchResultEntity result) {
    final vaultId = result.vaultId;
    if (vaultId == null) {
      context.go('/vaults');
      return;
    }
    final now = DateTime.now();
    EntryDetailPage.push(
      context,
      entry: EntryEntity(
        id: result.id,
        vaultId: vaultId,
        label: result.name,
        icon: result.icon,
        type: EntryType.credential,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  void _onVaultCta() {
    context.read<DashboardCubit>().onVaultCtaTapped();
    context.go('/vaults');
  }

  void _onApiKeyCta() {
    context.read<DashboardCubit>().onApiKeyCtaTapped();
    final auth = context.read<AuthBloc>().state;
    final permissions = auth is AuthAuthenticated ? auth.permissions : 0;
    final canReadApiKeys = (permissions & Permissions.readApiKey) != 0;
    context.go(canReadApiKeys ? '/api-keys' : '/vaults');
  }

  void _onAgentCta() {
    context.read<DashboardCubit>().onAgentCtaTapped();
    context.go('/agents');
  }

  Future<void> _onRegisterApprove(PendingGrant grant) async {
    // Reuse the existing approve-agent sheet to capture the new agent's
    // name/type/icon. Full "register & approve" wiring (crypto envelope +
    // enrollment) is out of scope here — opening the sheet is the stub.
    await ApproveAgentSheet.show(
      context,
      initialName: grant.agentName,
    );
    if (!mounted) return;
    context.read<DashboardCubit>().load();
  }

  void _onReject(PendingGrant grant) {
    // Stub for now — rejection flow is tracked separately.
    // TODO(approvals): wire reject endpoint + remove from pending list.
  }

  void _onRecentEntryTap(RecentEntryEntity recent) {
    final entry = EntryEntity(
      id: recent.id,
      vaultId: recent.vaultId,
      label: recent.label,
      icon: recent.icon,
      type: EntryTypeExtension.fromWire(recent.typeWire),
      createdAt: recent.createdAt,
      updatedAt: recent.updatedAt,
    );
    EntryDetailPage.push(context, entry: entry);
  }

  /// Builds the "Recently added / modified" section if [entries] is
  /// non-empty. Returns an empty list (no widgets) when [entries] is empty
  /// so the section is invisible rather than showing an empty card.
  List<Widget> _buildRecentEntriesSection(
    BuildContext context,
    List<RecentEntryEntity> entries,
  ) {
    if (entries.isEmpty) return const [];
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return [
      _SectionHeader(
        title: l10n.dashboardRecentlyModified,
        onSeeAll: () => context.go('/vaults'),
      ),
      const SizedBox(height: AppSpacing.cardGap),
      Container(
        decoration: BoxDecoration(
          color: AppColors.cardFill(brightness),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            for (int i = 0; i < entries.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: AppSpacing.screenH + AppSpacing.innerGap + 32,
                  color:
                      AppColors.onSurface(brightness).withValues(alpha: 0.06),
                ),
              _RecentEntryRow(
                entry: entries[i],
                onTap: () => _onRecentEntryTap(entries[i]),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.section),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthBloc>().state;
    final name = _displayName(auth);

    return AppScreen(
      header: _GreetingHeader(name: name),
      floatingActionButton: const FabRegistrar(fab: null),
      body: BlocProvider<SearchCubit>.value(
        value: _searchCubit,
        child: BlocBuilder<SearchCubit, SearchState>(
          builder: (context, searchState) {
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      0,
                      AppSpacing.screenH,
                      AppSpacing.fieldGap,
                    ),
                    child: AppSearchField(
                      controller: _searchController,
                      hint: l10n.dashboardSearchHint,
                      onChanged: (v) => _searchCubit.query(v),
                    ),
                  ),
                ),
                ..._searchSlivers(context, searchState),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Chooses the slivers below the search bar based on [searchState].
  ///
  /// While idle, the normal dashboard content (driven by [DashboardCubit])
  /// is shown; an active query replaces it with loading / results / empty /
  /// error states. The search bar itself stays visible either way.
  List<Widget> _searchSlivers(BuildContext context, SearchState searchState) {
    return switch (searchState) {
      SearchIdle() => [
        BlocBuilder<DashboardCubit, DashboardState>(
          builder: (context, state) => SliverMainAxisGroup(
            slivers: _contentSlivers(context, state),
          ),
        ),
      ],
      SearchLoading() => const [_SearchSkeletonSliver()],
      SearchResults(:final results) => [
        _SearchResultsSliver(
          results: results,
          onTap: (result) => _onSearchResultTap(context, result),
        ),
      ],
      SearchEmpty() => const [_SearchEmptySliver()],
      SearchError() => const [_SearchErrorSliver()],
    };
  }

  List<Widget> _contentSlivers(BuildContext context, DashboardState state) {
    return switch (state) {
      DashboardInitial() || DashboardLoading() => const [_SkeletonSliver()],
      DashboardOnboarding(
        :final status,
        :final notificationStepDone,
        :final notificationPermissionDenied,
      ) =>
        [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              0,
              AppSpacing.screenH,
              AppSpacing.listBottom,
            ),
            sliver: SliverToBoxAdapter(
              child: OnboardingChecklist(
                status: status,
                notificationStepDone: notificationStepDone,
                notificationPermissionDenied: notificationPermissionDenied,
                onSkipSetup: () => context.read<DashboardCubit>().skipSetup(),
                onEnableNotifications: () =>
                    context.read<DashboardCubit>().enableNotifications(),
                onSkipNotification: () =>
                    context.read<DashboardCubit>().skipNotificationStep(),
                onVaultCta: _onVaultCta,
                onApiKeyCta: _onApiKeyCta,
                onAgentCta: _onAgentCta,
              ),
            ),
          ),
        ],
      DashboardUnknownAgent(:final grant, :final recentEntries) => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.listBottom,
          ),
          sliver: SliverList.list(
            children: [
              _SectionHeader(
                title: AppLocalizations.of(context)!.dashboardPendingApprovals,
                badge: '1',
              ),
              const SizedBox(height: AppSpacing.cardGap),
              UnknownAgentCard(
                grant: grant,
                onRegisterApprove: () => _onRegisterApprove(grant),
                onReject: () => _onReject(grant),
              ),
              const SizedBox(height: AppSpacing.section),
              ..._buildRecentEntriesSection(context, recentEntries),
              _SectionHeader(
                title: AppLocalizations.of(context)!.dashboardRecentActivity,
              ),
              const SizedBox(height: AppSpacing.cardGap),
              const _ActivityEmpty(),
            ],
          ),
        ),
      ],
      DashboardLoaded(:final recentEntries) => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.listBottom,
          ),
          sliver: SliverList.list(
            children: [
              ..._buildRecentEntriesSection(context, recentEntries),
              _SectionHeader(
                title: AppLocalizations.of(context)!.dashboardRecentActivity,
              ),
              const SizedBox(height: AppSpacing.cardGap),
              const _ActivityEmpty(),
            ],
          ),
        ),
      ],
      DashboardError() => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorView(
            onRetry: () => context.read<DashboardCubit>().load(),
          ),
        ),
      ],
    };
  }

  String _displayName(AuthState state) {
    if (state is AuthAuthenticated &&
        state.email != null &&
        state.email!.isNotEmpty) {
      final local = state.email!.split('@').first;
      if (local.isEmpty) return '';
      return local[0].toUpperCase() + local.substring(1);
    }
    return '';
  }
}

/// Greeting header (rendered above the search bar) — "Good morning" over
/// the user's name, with a bell that opens the inbox.
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.headerGap,
        AppSpacing.screenH,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.dashboardGoodMorning,
                  style: TextStyle(
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontSize: 13,
                  ),
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    name,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => context.go('/inbox'),
            icon: Icon(
              Icons.notifications_outlined,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
            tooltip: l10n.navInbox,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.badge, this.onSeeAll});

  final String title;
  final String? badge;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: AppSpacing.chipGap),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.chipGap,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.brandRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: AppColors.brandRed,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        GestureDetector(
          onTap: onSeeAll,
          child: Text(
            l10n.dashboardSeeAll,
            style: TextStyle(
              color: onSeeAll != null
                  ? AppColors.brandRed
                  : AppColors.onSurfaceSubtle(brightness),
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

/// One row in the "Recently added / modified" section.
///
/// Shows the entry icon (Material icon from [EntryVisuals]) in a
/// tinted circle, the entry label + vault name, and a relative timestamp.
/// Tapping navigates to [EntryDetailPage] via [onTap].
class _RecentEntryRow extends StatelessWidget {
  const _RecentEntryRow({required this.entry, required this.onTap});

  final RecentEntryEntity entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final iconData = EntryVisuals.iconFor(entry.icon);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: AppSpacing.innerGap + AppSpacing.xs,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.positiveAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(iconData, size: 16, color: AppColors.positiveAccent),
            ),
            const SizedBox(width: AppSpacing.innerGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    entry.vaultName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.innerGap),
            Text(
              _formatRelative(l10n, entry.updatedAt),
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Localised relative timestamp. Reuses the same ARB keys as
  /// `vault_card.dart` (`vaultUpdatedNow`, `vaultUpdatedMinutesAgo`,
  /// `vaultUpdatedHoursAgo`, `vaultUpdatedDaysAgo`) since they are generic
  /// enough for this context.
  String _formatRelative(AppLocalizations l10n, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return l10n.vaultUpdatedNow;
    if (diff.inMinutes < 60) return l10n.vaultUpdatedMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.vaultUpdatedHoursAgo(diff.inHours);
    if (diff.inDays < 30) return l10n.vaultUpdatedDaysAgo(diff.inDays);
    final local = dt.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          Icon(
            Icons.history,
            size: 28,
            color: AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.3),
          ),
          const SizedBox(height: AppSpacing.chipGap),
          Text(
            l10n.dashboardNoActivity,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 12,
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
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.listBottom,
      ),
      sliver: SliverList.separated(
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.cardGap),
        itemBuilder: (_, index) => SkeletonBox(
          height: index == 0 ? 96 : 84,
          delay: Duration(milliseconds: index * 80),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.brandRed, size: 40),
            const SizedBox(height: AppSpacing.section),
            Text(
              l10n.errorCannotConnectToServer,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandRed,
              ),
              child: Text(l10n.vaultRetry),
            ),
          ],
        ),
      ),
    );
  }
}


/// Sliver list of global-search results, each a tappable [_SearchResultRow].
class _SearchResultsSliver extends StatelessWidget {
  const _SearchResultsSliver({required this.results, required this.onTap});

  final List<SearchResultEntity> results;
  final ValueChanged<SearchResultEntity> onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.listBottom,
      ),
      sliver: SliverToBoxAdapter(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (int i = 0; i < results.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppSpacing.screenH + AppSpacing.innerGap + 32,
                    color:
                        AppColors.onSurface(brightness).withValues(alpha: 0.06),
                  ),
                _SearchResultRow(
                  result: results[i],
                  onTap: () => onTap(results[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One global-search result row: a type badge, a tinted icon circle, the
/// object name, and a type/vault subtitle. Tapping navigates to the object.
class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.result, required this.onTap});

  final SearchResultEntity result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final color = _typeColor(result.type);
    final label = _typeLabel(l10n, result.type);
    final subtitle = result.type == SearchResultType.entry
        ? (result.vaultName ?? label)
        : label;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: AppSpacing.innerGap + AppSpacing.xs,
        ),
        child: Row(
          children: [
            _TypeBadge(label: label, color: color),
            const SizedBox(width: AppSpacing.innerGap),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_typeIcon(result), size: 16, color: color),
            ),
            const SizedBox(width: AppSpacing.innerGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    result.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 11,
                      height: 1.2,
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

  static Color _typeColor(SearchResultType type) => switch (type) {
        SearchResultType.agent => AppColors.vaultBlue,
        SearchResultType.vault => AppColors.brandRed,
        SearchResultType.entry => AppColors.positiveAccent,
      };

  static String _typeLabel(AppLocalizations l10n, SearchResultType type) =>
      switch (type) {
        SearchResultType.agent => l10n.searchTypeBadgeAgent,
        SearchResultType.vault => l10n.searchTypeBadgeVault,
        SearchResultType.entry => l10n.searchTypeBadgeEntry,
      };

  static IconData _typeIcon(SearchResultEntity result) => switch (result.type) {
        SearchResultType.agent => Icons.smart_toy,
        SearchResultType.vault => VaultVisuals.iconFor(result.icon),
        SearchResultType.entry => EntryVisuals.iconFor(result.icon),
      };
}

/// Small type pill (e.g. "Agent") tinted with the type color.
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.chipGap,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Skeleton shown while a search query is in flight.
class _SearchSkeletonSliver extends StatelessWidget {
  const _SearchSkeletonSliver();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.listBottom,
      ),
      sliver: SliverList.separated(
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.cardGap),
        itemBuilder: (_, index) => SkeletonBox(
          height: 56,
          delay: Duration(milliseconds: index * 80),
        ),
      ),
    );
  }
}

/// Empty state shown when a search returns no results.
class _SearchEmptySliver extends StatelessWidget {
  const _SearchEmptySliver();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.xxxl),
            Icon(
              Icons.search_off,
              size: 28,
              color:
                  AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpacing.chipGap),
            Text(
              l10n.searchResultsEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error state shown when a search request fails.
class _SearchErrorSliver extends StatelessWidget {
  const _SearchErrorSliver();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.xxxl),
            const Icon(
              Icons.error_outline,
              size: 28,
              color: AppColors.brandRed,
            ),
            const SizedBox(height: AppSpacing.chipGap),
            Text(
              l10n.searchResultsError,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
