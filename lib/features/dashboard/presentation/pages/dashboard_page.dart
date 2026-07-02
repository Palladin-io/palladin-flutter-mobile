import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../agents/presentation/widgets/approve_agent_sheet.dart';
import '../../../audit/presentation/widgets/audit_log_row.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../vault/domain/entities/entry_entity.dart';
import '../../../vault/domain/exceptions/entry_exceptions.dart';
import '../../../vault/domain/repositories/entry_repository.dart';
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
    // Read the audit permission from the app-wide AuthBloc so the cubit only
    // fetches the Recent Activity feed for users who can actually see it
    // (others would get a 403).
    _cubit = getIt<DashboardCubit>()
      ..load(canViewAudit: _canViewAudit(context));
  }

  /// Whether the authenticated user holds the `auditView` permission.
  static bool _canViewAudit(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final permissions = auth is AuthAuthenticated ? auth.permissions : 0;
    return (permissions & Permissions.auditView) != 0;
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
  /// Minimum characters before the field switches from the "Recent" list to
  /// live typed results (mirrors [SearchCubit] `_minQueryLength`).
  static const int _minQueryChars = 2;

  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode = FocusNode()
    ..addListener(_onSearchFocusChanged);
  late final SearchCubit _searchCubit = getIt<SearchCubit>();

  /// Anchors the floating autocomplete dropdown to the search field so it
  /// follows the field's position (web-panel parity).
  final LayerLink _searchLink = LayerLink();
  final OverlayPortalController _dropdownController = OverlayPortalController();

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _searchCubit.close();
    super.dispose();
  }

  /// Focus gained/lost — open the dropdown (Recent list / results) on focus,
  /// close it on blur.
  void _onSearchFocusChanged() => _updateOverlayVisibility();

  /// Shows the dropdown when the field is focused AND there is something to
  /// show: a typed query (loading / results / empty / error) or, on an empty
  /// field, at least one recent entry. Hides it otherwise. Safe to call from
  /// focus/query/state listeners (never during a build).
  void _updateOverlayVisibility() {
    if (!mounted) return;
    final shouldShow = _shouldShowDropdown();
    if (shouldShow && !_dropdownController.isShowing) {
      _dropdownController.show();
    } else if (!shouldShow && _dropdownController.isShowing) {
      _dropdownController.hide();
    }
  }

  bool _shouldShowDropdown() {
    if (!_searchFocusNode.hasFocus) return false;
    if (_searchController.text.trim().length >= _minQueryChars) return true;
    // Empty / sub-threshold query: only surface the Recent list when the
    // dashboard already has recent entries loaded (no empty floating card).
    return _recentEntriesFor(context.read<DashboardCubit>().state).isNotEmpty;
  }

  /// Closes the dropdown by dropping field focus (the focus listener hides
  /// the overlay). Used by the outside-tap barrier.
  void _closeDropdown() => _searchFocusNode.unfocus();

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
    _searchFocusNode.unfocus();
    _searchCubit.reset();
  }

  /// Projects a recent-entry snapshot onto the shared [SearchResultEntity]
  /// shape so a "Recent" suggestion can be rendered by [_SearchResultRow]
  /// and tapped through the exact same path as an `entry` search hit.
  SearchResultEntity _recentToSearchResult(RecentEntryEntity recent) =>
      SearchResultEntity(
        type: SearchResultType.entry,
        id: recent.id,
        name: recent.label,
        vaultId: recent.vaultId,
        vaultName: recent.vaultName,
        icon: recent.icon,
      );

  /// Recent entries carried by the current dashboard state, if any. Only
  /// [DashboardLoaded] and [DashboardUnknownAgent] carry them; every other
  /// state has none.
  List<RecentEntryEntity> _recentEntriesFor(DashboardState state) =>
      switch (state) {
        DashboardLoaded(:final recentEntries) => recentEntries,
        DashboardUnknownAgent(:final recentEntries) => recentEntries,
        _ => const [],
      };

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

  /// Fetches + decrypts an entry hit and returns its secret (password for a
  /// credential, value for a key). Returns null on failure and surfaces a
  /// short error snackbar. The caller (the row) decides what to do with the
  /// plaintext — copy it to the clipboard or reveal it inline — and caches it
  /// so copy and reveal share a single fetch. The private-key copy is zeroed
  /// in `finally`; the plaintext is never logged.
  Future<String?> _revealEntrySecret(SearchResultEntity result) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    void errorSnack(String message) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ));
    }

    final vaultId = result.vaultId;
    if (vaultId == null) {
      errorSnack(l10n.entryErrorNotFound);
      return null;
    }

    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      // Same "locked" message the add/edit paths surface.
      errorSnack(l10n.entryErrorCrypto);
      return null;
    }

    final keyCopy = Uint8List.fromList(auth.privateKey!);
    try {
      final revealed = await getIt<EntryRepository>().revealEntry(
        vaultId: vaultId,
        entryId: result.id,
        privateKey: keyCopy,
      );
      final payload = revealed.payload;
      final secret = revealed.entry.type == EntryType.key
          ? payload['value'] as String?
          : payload['password'] as String?;
      if (secret == null || secret.isEmpty) {
        errorSnack(l10n.entryErrorUnknown);
        return null;
      }
      return secret;
    } on EntryException catch (e) {
      AppLogger.w('Dashboard', 'reveal secret failed: ${e.kind.name}');
      errorSnack(_entryErrorMessage(e.kind, l10n));
      return null;
    } catch (e, s) {
      AppLogger.e('Dashboard', 'reveal secret failed', error: e, stackTrace: s);
      errorSnack(l10n.entryErrorUnknown);
      return null;
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }

  String _entryErrorMessage(EntryErrorKind kind, AppLocalizations l10n) =>
      switch (kind) {
        EntryErrorKind.notFound => l10n.entryErrorNotFound,
        EntryErrorKind.forbidden => l10n.entryErrorForbidden,
        EntryErrorKind.validation => l10n.entryErrorValidation,
        EntryErrorKind.cryptoFailure => l10n.entryErrorCrypto,
        EntryErrorKind.networkError => l10n.errorCannotConnectToServer,
        EntryErrorKind.unknown => l10n.entryErrorUnknown,
      };

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
    context.read<DashboardCubit>().load(
          canViewAudit: _DashboardPageState._canViewAudit(context),
        );
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

  /// Builds the "Recent Activity" section for users WITH audit access.
  ///
  /// Renders up to [DashboardCubit._recentActivityLimit] real org audit-log
  /// rows via the shared [AuditLogRow] (styling matches the full audit
  /// screen), with a "See all" link into the org-wide audit log. When the
  /// feed is genuinely empty it shows the [_ActivityEmpty] zero-state.
  ///
  /// `agentNames` is passed empty because the backend denormalizes
  /// `agentName` / `actorName` into each row server-side, so no client-side
  /// id→name lookup is needed here.
  List<Widget> _buildRecentActivitySection(
    BuildContext context,
    List<AuditLogEntry> logs,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return [
      _SectionHeader(
        title: l10n.dashboardRecentActivity,
        onSeeAll: () => context.go('/audit'),
      ),
      const SizedBox(height: AppSpacing.cardGap),
      if (logs.isEmpty)
        const _ActivityEmpty()
      else
        for (int i = 0; i < logs.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.cardGap),
          AuditLogRow(entry: logs[i], agentNames: const {}),
        ],
      const SizedBox(height: AppSpacing.section),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthBloc>().state;
    final name = _displayName(auth);
    final permissions = auth is AuthAuthenticated ? auth.permissions : 0;
    final hasAuditView = (permissions & Permissions.auditView) != 0;

    return AppScreen(
      header: _GreetingHeader(name: name),
      floatingActionButton: const FabRegistrar(fab: null),
      body: BlocProvider<SearchCubit>.value(
        value: _searchCubit,
        // Recents may arrive after mount; re-evaluate the dropdown so a
        // focused empty field can open once the recent list is ready.
        child: BlocListener<DashboardCubit, DashboardState>(
          listener: (_, _) => _updateOverlayVisibility(),
          child: CustomScrollView(
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
                  // The search field is the dropdown's anchor (target) and
                  // hosts the OverlayPortal that floats over the content.
                  child: CompositedTransformTarget(
                    link: _searchLink,
                    child: OverlayPortal(
                      controller: _dropdownController,
                      overlayChildBuilder: _buildDropdownOverlay,
                      child: AppSearchField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        hint: l10n.dashboardSearchHint,
                        onChanged: (v) {
                          _searchCubit.query(v);
                          _updateOverlayVisibility();
                        },
                      ),
                    ),
                  ),
                ),
              ),
              // Dashboard content always renders underneath — the search
              // dropdown floats above it, never swapping it out.
              BlocBuilder<DashboardCubit, DashboardState>(
                builder: (context, state) => SliverMainAxisGroup(
                  slivers: _contentSlivers(context, state, hasAuditView),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the floating autocomplete overlay: a full-screen tap barrier
  /// (outside-tap dismiss) and a [CompositedTransformFollower] card anchored
  /// directly below the search field. Content is driven reactively by the
  /// [SearchCubit] (typed results) and [DashboardCubit] (Recent list).
  Widget _buildDropdownOverlay(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width - AppSpacing.screenH * 2;
    final maxHeight = media.size.height * 0.5;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeDropdown,
          ),
        ),
        CompositedTransformFollower(
          link: _searchLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, AppSpacing.sm),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: _SearchDropdownCard(
                maxHeight: maxHeight,
                child: BlocBuilder<SearchCubit, SearchState>(
                  builder: (context, searchState) =>
                      BlocBuilder<DashboardCubit, DashboardState>(
                    builder: (context, dashboardState) => AnimatedSize(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 140),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        // Top-align the outgoing/incoming children so the
                        // cross-fade doesn't vertically re-center mid-flight
                        // (the "jump" that reads as lag).
                        layoutBuilder: (currentChild, previousChildren) => Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            ...previousChildren,
                            ?currentChild,
                          ],
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_dropdownContentKey(searchState)),
                          child: _dropdownContent(
                            context,
                            searchState,
                            _recentEntriesFor(dashboardState),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Identifies the current dropdown "range" so the [AnimatedSwitcher] cross-
  /// fades when it changes (recent ↔ results ↔ loading ↔ empty ↔ error).
  String _dropdownContentKey(SearchState searchState) {
    final isSearching =
        _searchController.text.trim().length >= _minQueryChars;
    if (!isSearching) return 'recent';
    return switch (searchState) {
      SearchResults() => 'results',
      SearchEmpty() => 'empty',
      SearchError() => 'error',
      SearchLoading() || SearchIdle() => 'loading',
    };
  }

  /// Chooses the dropdown body: the Recent list on an empty/sub-threshold
  /// field, otherwise the live [SearchCubit] result states.
  Widget _dropdownContent(
    BuildContext context,
    SearchState searchState,
    List<RecentEntryEntity> recentEntries,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final isSearching =
        _searchController.text.trim().length >= _minQueryChars;

    if (!isSearching) {
      final results = recentEntries
          .take(5)
          .map(_recentToSearchResult)
          .toList(growable: false);
      if (results.isEmpty) return const SizedBox.shrink();
      return _SearchResultList(
        header: l10n.dashboardSearchRecent,
        results: results,
        onTap: (result) => _onSearchResultTap(context, result),
        onRevealSecret: _revealEntrySecret,
      );
    }

    return switch (searchState) {
      SearchResults(:final results) => _SearchResultList(
        results: results,
        onTap: (result) => _onSearchResultTap(context, result),
        onRevealSecret: _revealEntrySecret,
      ),
      SearchEmpty() => _DropdownMessage(
        icon: Icons.search_off,
        text: l10n.searchResultsEmpty,
      ),
      SearchError() => _DropdownMessage(
        icon: Icons.error_outline,
        iconColor: AppColors.brandRed,
        text: l10n.searchResultsError,
      ),
      // Between crossing the 2-char threshold and the debounce firing the
      // state is still SearchIdle — treat it as loading, same as SearchLoading.
      SearchLoading() || SearchIdle() => const _DropdownLoading(),
    };
  }

  List<Widget> _contentSlivers(
    BuildContext context,
    DashboardState state,
    bool hasAuditView,
  ) {
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
      DashboardUnknownAgent(
        :final grant,
        :final recentEntries,
        :final recentActivity,
      ) =>
        [
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
                  title:
                      AppLocalizations.of(context)!.dashboardPendingApprovals,
                  badge: '1',
                ),
                const SizedBox(height: AppSpacing.cardGap),
                UnknownAgentCard(
                  grant: grant,
                  onRegisterApprove: () => _onRegisterApprove(grant),
                  onReject: () => _onReject(grant),
                ),
                const SizedBox(height: AppSpacing.section),
                // Users WITH audit access see the real audit-log activity;
                // everyone else gets the "Recently added / modified" surface.
                if (hasAuditView)
                  ..._buildRecentActivitySection(context, recentActivity)
                else
                  ..._buildRecentEntriesSection(context, recentEntries),
              ],
            ),
          ),
        ],
      DashboardLoaded(:final recentEntries, :final recentActivity) => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.listBottom,
          ),
          sliver: SliverList.list(
            children: [
              // Users WITH audit access see the real audit-log activity;
              // everyone else gets the "Recently added / modified" surface.
              if (hasAuditView)
                ..._buildRecentActivitySection(context, recentActivity)
              else
                ..._buildRecentEntriesSection(context, recentEntries),
            ],
          ),
        ),
      ],
      DashboardError() => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorView(
            onRetry: () => context
                .read<DashboardCubit>()
                .load(canViewAudit: hasAuditView),
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


/// Small muted header above the focus-driven "Recent" suggestions. Sentence
/// case only — no all-caps (project rule against `text-transform`).
class _RecentSuggestionsHeader extends StatelessWidget {
  const _RecentSuggestionsHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Text(
      label,
      style: TextStyle(
        color: AppColors.onSurfaceSubtle(brightness),
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Opaque, rounded, shadowed surface for the floating autocomplete dropdown.
///
/// Uses the solid [AppColors.modalBackground] token (never a translucent
/// card) so it fully covers the dashboard content underneath, with a subtle
/// border + drop shadow and an internal scroll bounded by [maxHeight]. Wraps
/// [child] in a transparent [Material] so the result rows' ink ripples render
/// even though the surface lives in the root [Overlay].
class _SearchDropdownCard extends StatelessWidget {
  const _SearchDropdownCard({required this.maxHeight, required this.child});

  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder(brightness)),
        boxShadow: [
          BoxShadow(
            color: AppColors.dropdownShadow(brightness),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}

/// The dropdown's result list: an optional muted header (the "Recent" label)
/// over tappable [_SearchResultRow]s, hairline-separated, scrollable when the
/// rows exceed the card's bounded height.
class _SearchResultList extends StatelessWidget {
  const _SearchResultList({
    required this.results,
    required this.onTap,
    this.header,
    this.onRevealSecret,
  });

  final List<SearchResultEntity> results;
  final ValueChanged<SearchResultEntity> onTap;
  final String? header;

  /// Fetches + decrypts an entry hit's secret (returns null on failure).
  /// Wired only for entry-type rows; agent/vault rows show neither the
  /// reveal nor the copy action.
  final Future<String?> Function(SearchResultEntity)? onRevealSecret;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                AppSpacing.cardPadding,
                AppSpacing.cardPadding,
                AppSpacing.innerGap,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _RecentSuggestionsHeader(label: header!),
              ),
            ),
          for (int i = 0; i < results.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppSpacing.cardPadding + AppSpacing.innerGap + 32,
                color: AppColors.onSurface(brightness).withValues(alpha: 0.06),
              ),
            _SearchResultRow(
              result: results[i],
              onTap: () => onTap(results[i]),
              onRevealSecret: results[i].type == SearchResultType.entry &&
                      onRevealSecret != null
                  ? () => onRevealSecret!(results[i])
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// Single-line dropdown message row (e.g. "No results" / an error hint) with a
/// leading glyph — used for the empty and error states.
class _DropdownMessage extends StatelessWidget {
  const _DropdownMessage({
    required this.icon,
    required this.text,
    this.iconColor,
  });

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.innerGap + AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: iconColor ??
                AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.6),
          ),
          const SizedBox(width: AppSpacing.innerGap),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder for the dropdown: a couple of skeleton rows shown while
/// a query is in flight (or during the pre-debounce window).
class _DropdownLoading extends StatelessWidget {
  const _DropdownLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.innerGap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(height: 40),
          SizedBox(height: AppSpacing.cardGap),
          SkeletonBox(height: 40),
        ],
      ),
    );
  }
}

/// One global-search result row: a type badge, a tinted icon circle, the
/// object name, and a type/vault subtitle. Tapping navigates to the object.
///
/// Entry hits also render trailing reveal + copy quick actions
/// ([onRevealSecret]) that decrypt the entry on demand: reveal shows the
/// secret inline in the subtitle (masked → shown, toggling back on a second
/// tap), copy writes it to the clipboard — neither navigates. The secret is
/// decrypted once and cached for the row, so reveal and copy never double-
/// fetch. A small inline spinner replaces the tapped glyph while in flight.
class _SearchResultRow extends StatefulWidget {
  const _SearchResultRow({
    required this.result,
    required this.onTap,
    this.onRevealSecret,
  });

  final SearchResultEntity result;
  final VoidCallback onTap;

  /// Decrypts + returns the entry's secret (null on failure). Null for
  /// non-entry hits, which get neither reveal nor copy.
  final Future<String?> Function()? onRevealSecret;

  @override
  State<_SearchResultRow> createState() => _SearchResultRowState();
}

class _SearchResultRowState extends State<_SearchResultRow> {
  /// Decrypted secret, cached for the row's lifetime so reveal + copy share a
  /// single fetch. Held in memory only; only shown when [_revealed] is true.
  String? _secret;
  bool _revealed = false;
  bool _copyBusy = false;
  bool _revealBusy = false;

  bool get _busy => _copyBusy || _revealBusy;

  /// Decrypts the secret on first need and caches it; subsequent calls reuse
  /// the cached plaintext (no second `revealEntry` round-trip).
  Future<String?> _ensureSecret() async {
    if (_secret != null) return _secret;
    final secret = await widget.onRevealSecret!.call();
    if (secret != null) _secret = secret;
    return secret;
  }

  Future<void> _onCopy() async {
    if (_busy || widget.onRevealSecret == null) return;
    setState(() => _copyBusy = true);
    try {
      final secret = await _ensureSecret();
      if (secret == null || !mounted) return;
      await Clipboard.setData(ClipboardData(text: secret));
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(l10n.entryCopied),
          duration: const Duration(seconds: 1),
        ));
    } finally {
      if (mounted) setState(() => _copyBusy = false);
    }
  }

  Future<void> _onToggleReveal() async {
    if (_busy || widget.onRevealSecret == null) return;
    // Hiding is instant — the plaintext stays cached for a later re-reveal.
    if (_revealed) {
      setState(() => _revealed = false);
      return;
    }
    setState(() => _revealBusy = true);
    try {
      final secret = await _ensureSecret();
      if (secret == null || !mounted) return;
      setState(() => _revealed = true);
    } finally {
      if (mounted) setState(() => _revealBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final color = _typeColor(result.type);
    final label = _typeLabel(l10n, result.type);
    final hasActions = widget.onRevealSecret != null;
    final showSecret = _revealed && _secret != null;
    final subtitle = result.type == SearchResultType.entry
        ? (result.vaultName ?? label)
        : label;

    return InkWell(
      onTap: widget.onTap,
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
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _typeIcon(result),
                size: 16,
                color: color,
              ),
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
                  // When revealed, the subtitle carries the decrypted secret
                  // inline (monospace), mirroring the entries-tab reveal.
                  Text(
                    showSecret ? _secret! : subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: showSecret
                        ? TextStyle(
                            color: AppColors.onSurface(brightness),
                            fontSize: 11,
                            height: 1.2,
                            fontFamily: 'monospace',
                            letterSpacing: 0.5,
                          )
                        : TextStyle(
                            color: AppColors.onSurfaceSubtle(brightness),
                            fontSize: 11,
                            height: 1.2,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.innerGap),
            if (hasActions) ...[
              _RowActionButton(
                icon: _revealed ? Icons.visibility_off : Icons.visibility,
                busy: _revealBusy,
                tooltip: l10n.vaultRevealValue,
                onPressed: _onToggleReveal,
                brightness: brightness,
              ),
              const SizedBox(width: AppSpacing.chipGap),
              _RowActionButton(
                icon: Icons.content_copy,
                busy: _copyBusy,
                tooltip: l10n.vaultCopyValue,
                onPressed: _onCopy,
                brightness: brightness,
              ),
              const SizedBox(width: AppSpacing.chipGap),
            ],
            _TypeBadge(label: label, color: color),
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

/// Trailing quick-action for an entry search hit (reveal / copy) — the glyph
/// swaps to a small spinner while the entry is being decrypted. The 14px
/// glyph sits inside a comfortable tap target (InkResponse + xs padding).
class _RowActionButton extends StatelessWidget {
  const _RowActionButton({
    required this.icon,
    required this.busy,
    required this.tooltip,
    required this.onPressed,
    required this.brightness,
  });

  final IconData icon;
  final bool busy;
  final String tooltip;
  final VoidCallback onPressed;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: busy ? null : onPressed,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.brandRed,
                  ),
                )
              : Icon(
                  icon,
                  size: 14,
                  color: AppColors.onSurfaceSubtle(brightness),
                ),
        ),
      ),
    );
  }
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

