import 'package:flutter/material.dart';

import '../../../../core/widgets/brand_tab_indicator.dart';

import '../../../../core/widgets/app_brand_background.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../approval/presentation/widgets/grant_access_sheet.dart';
import '../../../audit/presentation/widgets/entry_logs_tab.dart';
import '../../domain/entities/entry_entity.dart';
import '../cubit/edit_entry_cubit.dart';
import '../cubit/entry_agents_cubit.dart';
import '../cubit/entry_history_cubit.dart';
import 'entry_agents_tab.dart';
import 'entry_details_tab.dart';
import 'entry_history_tab.dart';
import 'entry_sharing_tab.dart';

/// Result of [EntryDetailPage.push].
sealed class EntryDetailResult {}

/// The entry metadata was updated and the new entity is ready to replace
/// the stale row in the parent list.
class EntryDetailUpdated extends EntryDetailResult {
  EntryDetailUpdated(this.entry);
  final EntryEntity entry;
}

/// The entry was permanently deleted — caller should remove it from the
/// local list state.
class EntryDetailDeleted extends EntryDetailResult {
  EntryDetailDeleted(this.entryId);
  final String entryId;
}

/// Full-screen entry detail screen.
///
/// Tab 0 — Details: a read-only quick-access view (copy / reveal secrets)
///                  that switches into the edit form on demand.
/// Tab 1 — Agents.
/// Tab 2 — Logs.
/// Tab 3 — History (loaded only when selected).
///
/// MemberIndex metadata renders immediately. MemberSecret is fetched and
/// authenticated on entry; secret fields remain masked until revealed.
class EntryDetailPage extends StatelessWidget {
  const EntryDetailPage({
    super.key,
    required this.entry,
    this.wrappedVK,
    this.showSharing = false,
  });

  final EntryEntity entry;
  final String? wrappedVK;
  final bool showSharing;

  static Future<EntryDetailResult?> push(
    BuildContext context, {
    required EntryEntity entry,
    String? wrappedVK,
    bool showSharing = false,
  }) {
    return Navigator.of(context, rootNavigator: true).push<EntryDetailResult>(
      MaterialPageRoute(
        builder: (_) => EntryDetailPage(
          entry: entry,
          wrappedVK: wrappedVK,
          showSharing: showSharing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<EditEntryCubit>(create: (_) => getIt<EditEntryCubit>()),
        BlocProvider<EntryAgentsCubit>(
          create: (_) => getIt<EntryAgentsCubit>(),
        ),
        BlocProvider<EntryHistoryCubit>(
          create: (_) => getIt<EntryHistoryCubit>(),
        ),
      ],
      child: Builder(
        builder: (context) => BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is! AuthAuthenticated || state.privateKey == null) {
              context.read<EditEntryCubit>().clearSensitiveState();
              context.read<EntryAgentsCubit>().clearSensitiveState();
              context.read<EntryHistoryCubit>().clearSensitiveState();
            }
          },
          child: _EntryDetailView(
            entry: entry,
            wrappedVK: wrappedVK,
            showSharing: showSharing,
          ),
        ),
      ),
    );
  }
}

// ── Detail view ────────────────────────────────────────────────────

class _EntryDetailView extends StatefulWidget {
  const _EntryDetailView({
    required this.entry,
    this.wrappedVK,
    required this.showSharing,
  });

  final EntryEntity entry;
  final String? wrappedVK;
  final bool showSharing;

  @override
  State<_EntryDetailView> createState() => _EntryDetailViewState();
}

class _EntryDetailViewState extends State<_EntryDetailView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Lets the Details tab drive a Cancel action in the AppBar (beside the name)
  /// while it is in edit mode.
  final EntryEditController _editController = EntryEditController();

  /// The current entity — updated after an edit so the app-bar title stays
  /// in sync with saved changes.
  late EntryEntity _entry = widget.entry;

  /// The latest saved entity, returned as an [EntryDetailUpdated] result when
  /// the user leaves the screen (edits happen in place, not on a pop).
  EntryEntity? _latestUpdate;

  // Bumped after a grant is created on the Agents tab so the (self-providing) grants list remounts.
  int _grantsRefresh = 0;

  static const int _agentsTabIndex = 1;
  static const int _logsTabIndex = 2;
  static const int _historyTabIndex = 3;
  static const int _sharingTabIndex = 4;

  // Last tab index reported to analytics — dedupes the multiple listener
  // callbacks a single switch fires during the indicator animation.
  int _lastTrackedTab = 0;

  @override
  void initState() {
    super.initState();
    _lastTrackedTab = widget.showSharing ? _sharingTabIndex : 0;
    _tabController =
        TabController(length: 5, vsync: this, initialIndex: _lastTrackedTab)
          // Rebuild so the FAB shows only on the Agents tab.
          ..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    setState(() {});
    final index = _tabController.index;
    if (index != _historyTabIndex) {
      context.read<EntryHistoryCubit>().clearSensitiveState(keepItems: true);
    }
    if (_tabController.indexIsChanging || index == _lastTrackedTab) return;
    _lastTrackedTab = index;
    if (index == _historyTabIndex) {
      context.read<EntryHistoryCubit>().open(_entry);
    }
    const tabNames = ['details', 'agents', 'logs', 'history', 'sharing'];
    AnalyticsService.instance.capture(
      'entry',
      'detail-tab-switched',
      properties: {
        'entry_type': widget.entry.type.name,
        'tab': tabNames[index],
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _editController.dispose();
    super.dispose();
  }

  Future<void> _onAddAgent() async {
    final granted = await GrantAccessSheet.show(
      context,
      GrantForEntry(
        vaultId: widget.entry.vaultId,
        entryId: widget.entry.id,
        entryType: widget.entry.type,
      ),
    );
    if (granted == true && mounted) {
      setState(() => _grantsRefresh++);
    }
  }

  void _onUpdated(EntryEntity updated) {
    final history = context.read<EntryHistoryCubit>()..invalidate();
    setState(() {
      _entry = updated;
      _latestUpdate = updated;
    });
    if (_tabController.index == _historyTabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabController.index == _historyTabIndex) {
          history.open(_entry);
        }
      });
    }
  }

  void _onDeleted(String entryId) {
    Navigator.of(context).pop(EntryDetailDeleted(entryId));
  }

  /// Pops with the pending update (if any) so the parent list refreshes.
  void _handleBack() {
    Navigator.of(
      context,
    ).pop(_latestUpdate != null ? EntryDetailUpdated(_latestUpdate!) : null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return PopScope<EntryDetailResult>(
      // Let the normal pop through when nothing changed (preserves the iOS
      // swipe-back gesture); intercept only to attach the update result.
      canPop: _latestUpdate == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(EntryDetailUpdated(_latestUpdate!));
      },
      child: AppBrandBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: _tabController.index == _agentsTabIndex
              ? AppFab(
                  onPressed: _onAddAgent,
                  tooltip: l10n.grantAccessTitleAgent,
                )
              : null,
          appBar: _EntryDetailAppBar(
            label: _entry.label,
            tabController: _tabController,
            onBack: _handleBack,
            editController: _editController,
            l10n: l10n,
            brightness: brightness,
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: TabBarView(
              controller: _tabController,
              children: [
                EntryDetailsTab(
                  entry: _entry,
                  wrappedVK: widget.wrappedVK,
                  editController: _editController,
                  onUpdated: _onUpdated,
                  onDeleted: _onDeleted,
                ),
                EntryAgentsTab(
                  entry: _entry,
                  grantsRefresh: _grantsRefresh,
                  onUpdated: _onUpdated,
                ),
                EntryLogsTab(
                  vaultId: widget.entry.vaultId,
                  entryId: widget.entry.id,
                  active: _tabController.index == _logsTabIndex,
                  contentPadding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    AppSpacing.fieldGap,
                    AppSpacing.screenH,
                    AppSpacing.listBottom,
                  ),
                ),
                EntryHistoryTab(entry: _entry, onUpdated: _onUpdated),
                EntrySharingTab(
                  key: ValueKey('sharing-${_entry.vaultId}-${_entry.id}'),
                  entry: _entry,
                  active: _tabController.index == _sharingTabIndex,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── AppBar ─────────────────────────────────────────────────────────

class _EntryDetailAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _EntryDetailAppBar({
    required this.label,
    required this.tabController,
    required this.onBack,
    required this.editController,
    required this.l10n,
    required this.brightness,
  });

  final String label;
  final TabController tabController;
  final VoidCallback onBack;
  final EntryEditController editController;
  final AppLocalizations l10n;
  final Brightness brightness;

  static const double _tabBarHeight = 44;

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight + _tabBarHeight);

  @override
  Widget build(BuildContext context) {
    final onSurface = AppColors.onSurface(brightness);
    final subtle = AppColors.onSurfaceSubtle(brightness);

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 0,
      iconTheme: IconThemeData(color: onSurface),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        onPressed: onBack,
      ),
      title: AppBarTitle(title: label),
      // Cancel sits beside the name at the very top — visible only while the
      // Details tab is in edit mode.
      actions: [
        ListenableBuilder(
          listenable: editController,
          builder: (context, _) => editController.editing
              ? Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: TextButton.icon(
                    onPressed: editController.requestCancel,
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(l10n.vaultCancel),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandRed,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(_tabBarHeight),
        child: SizedBox(
          height: _tabBarHeight,
          child: TabBar(
            controller: tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.cardPadding,
            ),
            labelColor: AppColors.brandRed,
            unselectedLabelColor: subtle,
            indicator: BrandTabIndicator(
              glowColor: AppColors.primaryGlow(brightness),
            ),
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 2,
            dividerColor: AppColors.navBorder(brightness),
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(text: l10n.entryTabDetails),
              Tab(text: l10n.vaultTabAgents),
              Tab(text: l10n.vaultTabLogs),
              Tab(text: l10n.entryTabHistory),
              Tab(text: l10n.sharingTab),
            ],
          ),
        ),
      ),
    );
  }
}
