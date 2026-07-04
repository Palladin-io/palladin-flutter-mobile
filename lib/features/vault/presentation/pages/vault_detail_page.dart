import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../cubit/vault_list_cubit.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../shell/presentation/pages/app_shell.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../cubit/entry_list_cubit.dart';
import '../cubit/vault_detail_cubit.dart';
import '../widgets/vault_entries_tab.dart';
import '../widgets/vault_form.dart';
import '../../../approval/presentation/widgets/grant_access_sheet.dart';
import '../../../audit/presentation/widgets/vault_audit_log_tab.dart';
import '../../../grants/presentation/widgets/context_grants_tab.dart';
import '../widgets/export_sheet.dart';
import '../widgets/vault_placeholder_tab.dart';
import '../widgets/vault_settings_tab.dart';
import '../widgets/vault_visuals.dart';
import 'add_entry_page.dart';
import 'import_wizard_page.dart';

/// Vault detail screen — wraps a [DefaultTabController] with five tabs:
/// Entries, Agents, Logs, Members, Settings. Each tab body lives in
/// its own widget under `widgets/vault_*_tab.dart`.
///
/// Page-level state (form-data dirty flag, current tab index) is held
/// here so the AppBar Save action can react without coupling the
/// settings widget to the cubit.
class VaultDetailPage extends StatelessWidget {
  const VaultDetailPage({super.key, required this.vaultId});

  final String vaultId;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<VaultDetailCubit>(
          create: (_) => getIt<VaultDetailCubit>()..load(vaultId),
        ),
        // The entries cubit is parametrised on `vaultId` so the
        // datasource calls hit the right route. Loading is kicked off
        // on creation so the Entries tab has data ready when first
        // rendered.
        //
        // We also seed the cubit with the vault's `wrappedVK` if the
        // detail cubit is already in [VaultDetailLoaded] (e.g. user
        // navigated back to the same vault). When the vault hasn't
        // loaded yet, the page wires the value in via a BlocListener
        // once it becomes available — see [_VaultDetailViewState.build].
        BlocProvider<EntryListCubit>(
          create: (ctx) {
            final detailState = ctx.read<VaultDetailCubit>().state;
            final wrappedVK = detailState is VaultDetailLoaded
                ? detailState.vault.wrappedVK
                : null;
            return getIt<EntryListCubit>(param1: vaultId, param2: wrappedVK)
              ..loadEntries();
          },
        ),
      ],
      child: _VaultDetailView(vaultId: vaultId),
    );
  }
}

enum _VaultTab { entries, agents, logs, members, settings }

/// Overflow-menu actions on the vault detail AppBar.
enum _VaultAction { import, export }

class _VaultDetailView extends StatefulWidget {
  const _VaultDetailView({required this.vaultId});

  final String vaultId;

  @override
  State<_VaultDetailView> createState() => _VaultDetailViewState();
}

class _VaultDetailViewState extends State<_VaultDetailView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  VaultFormData? _initialFormData;
  VaultFormData? _currentFormData;

  // Bumped after a grant is created on the Agents tab so the (self-providing) grants list remounts
  // and reloads — keyed in [_LoadedBody].
  int _grantsRefresh = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _VaultTab.values.length, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Wraps a `showModalBottomSheet` call so the shell-owned bottom nav
  /// hides while the sheet is visible. All sheet entry points on this
  /// page (FAB, future menu actions, …) must funnel through here.
  ///
  /// The 280 ms wait in `finally` lets the sheet's close animation
  /// finish before the nav reappears — without it the nav pops back in
  /// while the sheet is still sliding out, producing a visible height
  /// jump as the body re-lays out.
  // ignore: unused_element
  Future<T?> _showSheet<T>(Widget Function(BuildContext) builder) async {
    final shell = AppShellScope.of(context);
    shell.setBottomNavHidden(true);
    try {
      return await showModalBottomSheet<T>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: builder,
      );
    } finally {
      await Future.delayed(const Duration(milliseconds: 280));
      if (mounted) shell.setBottomNavHidden(false);
    }
  }

  Future<void> _onFabPressed() async {
    if (!mounted) return;
    // Agents tab: proactively grant an agent access to this vault (FULL).
    if (_tabController.index == _VaultTab.agents.index) {
      final granted = await GrantAccessSheet.show(
        context,
        GrantForVault(widget.vaultId),
      );
      if (granted == true && mounted) {
        setState(() => _grantsRefresh++);
      }
      return;
    }
    if (_tabController.index != _VaultTab.entries.index) {
      return;
    }
    // Capture the cubit before the async gap so no context access is needed
    // after the await — the widget may be gone by the time push() returns.
    final entryListCubit = context.read<EntryListCubit>();
    // Thread the cached wrappedVK from the vault detail cubit so the
    // create-entry pipeline can skip the redundant `GET /api/vaults/{id}`.
    final detailState = context.read<VaultDetailCubit>().state;
    final wrappedVK = detailState is VaultDetailLoaded
        ? detailState.vault.wrappedVK
        : null;
    final created = await AddEntryPage.push(
      context,
      vaultId: widget.vaultId,
      wrappedVK: wrappedVK,
    );
    if (!mounted) return;
    if (created is EntryEntity) {
      await entryListCubit.appendEntry(created);
    }
  }

  /// Builds the FAB registered with the shell on the Entries / Agents
  /// tabs, or `null` on tabs that shouldn't show one. The shell
  /// receives `null` and clears its FAB slot so we don't show a
  /// stale add affordance on the Logs / Members / Settings tabs.
  Widget? _detailFab(AppLocalizations l10n) {
    // FAB on Entries (add entry) and Agents (grant an agent access). Other tabs show none.
    final onEntries = _tabController.index == _VaultTab.entries.index;
    final onAgents = _tabController.index == _VaultTab.agents.index;
    if (!onEntries && !onAgents) return null;

    return Padding(
      padding: const EdgeInsets.only(
        bottom: AppSpacing.innerGap,
        right: AppSpacing.xs,
      ),
      child: AppFab(
        onPressed: _onFabPressed,
        tooltip: onAgents ? l10n.grantAccessTitleVault : l10n.vaultAddEntryFab,
      ),
    );
  }

  /// Opens the import wizard for this vault, then refreshes the entries
  /// list and the header count when at least one entry was imported.
  Future<void> _onImport() async {
    final detailState = context.read<VaultDetailCubit>().state;
    if (detailState is! VaultDetailLoaded) return;
    final vault = detailState.vault;
    final entryListCubit = context.read<EntryListCubit>();
    final detailCubit = context.read<VaultDetailCubit>();
    final imported = await ImportWizardPage.push(
      context,
      vaultId: widget.vaultId,
      vaultName: vault.name,
      wrappedVK: vault.wrappedVK,
    );
    if (imported == true) {
      await entryListCubit.loadEntries();
      await detailCubit.load(widget.vaultId);
    }
  }

  Future<void> _onExport() async {
    final detailState = context.read<VaultDetailCubit>().state;
    if (detailState is! VaultDetailLoaded) return;
    final vault = detailState.vault;
    await ExportSheet.show(
      context,
      vaultId: widget.vaultId,
      vaultName: vault.name,
      wrappedVK: vault.wrappedVK,
    );
  }

  void _saveSettings() {
    final data = _currentFormData;
    if (data == null) return;
    context.read<VaultDetailCubit>().update(
      widget.vaultId,
      name: data.name.trim(),
      description: data.description.trim(),
      icon: data.icon,
      color: data.color,
      grantMode: data.grantMode,
    );
  }

  Future<void> _confirmDelete(VaultEntity vault) async {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.modalBackground(brightness),
          title: Text(
            l10n.vaultDeleteTitle,
            style: TextStyle(color: AppColors.onSurface(brightness)),
          ),
          content: Text(
            l10n.vaultDeleteConfirmWithName(vault.name),
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                l10n.vaultCancel,
                style: TextStyle(color: AppColors.onSurfaceMuted(brightness)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                l10n.vaultDeleteVault,
                style: const TextStyle(color: AppColors.brandRed),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      // ignore: use_build_context_synchronously
      context.read<VaultDetailCubit>().delete(widget.vaultId);
    }
  }

  void _syncFormFromVault(VaultEntity vault, AppLocalizations l10n) {
    final next = VaultFormData(
      name: vault.name,
      description: vault.description ?? '',
      icon: vault.icon ?? VaultVisuals.defaultIconName,
      color: vault.color ?? VaultVisuals.defaultColorHex,
      grantMode: vault.grantMode,
    );
    if (_initialFormData == null) {
      setState(() {
        _initialFormData = next;
        _currentFormData = next;
      });
    } else if (next != _initialFormData) {
      setState(() {
        _initialFormData = next;
        _currentFormData = next;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.vaultSavedSnackbar),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocConsumer<VaultDetailCubit, VaultDetailState>(
      listener: (context, state) {
        if (state is VaultDetailLoaded) {
          _syncFormFromVault(state.vault, l10n);
          // Forward the freshly-loaded wrappedVK so subsequent reveal
          // calls skip the second `GET /api/vaults/{id}`. Safe to call
          // every load — reload/update preserves the latest sealed VK.
          context.read<EntryListCubit>().updateWrappedVK(state.vault.wrappedVK);
        } else if (state is VaultDetailDeleted) {
          getIt<VaultListCubit>().removeVault(widget.vaultId);
          context.go('/vaults');
        }
      },
      builder: (context, state) {
        final brightness = Theme.of(context).brightness;
        return Container(
          decoration: BoxDecoration(
            gradient: AppColors.backgroundGradient(brightness),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: _DetailAppBar(
              state: state,
              onBack: () => context.pop(),
              tabController: _tabController,
              onImport: _onImport,
              onExport: _onExport,
            ),
            body: Stack(
              children: [
                SafeArea(
                  top: false,
                  child: switch (state) {
                    VaultDetailInitial() ||
                    VaultDetailLoading() => const _LoadingView(),
                    VaultDetailDeleted() => const SizedBox.shrink(),
                    VaultDetailError(:final kind) => _ErrorView(kind: kind),
                    VaultDetailLoaded(:final vault) => _LoadedBody(
                      vault: vault,
                      tabController: _tabController,
                      grantsRefresh: _grantsRefresh,
                      initialFormData: _initialFormData,
                      onFormChanged: (data) =>
                          setState(() => _currentFormData = data),
                      onDelete: () => _confirmDelete(vault),
                      onSave: _saveSettings,
                    ),
                  },
                ),
                // Register the FAB with the shell so it stays pinned in
                // place during page transitions. Pass `null` on tabs
                // that shouldn't show one (Logs, Members, Settings) —
                // otherwise the previous page's FAB would linger.
                Positioned(
                  width: 0,
                  height: 0,
                  child: FabRegistrar(fab: _detailFab(l10n)),
                ),
              ],
            ),
            // No `bottomNavigationBar` here — the shell-owned
            // [AppBottomNav] is shared across every route under the
            // shell (now including `/vaults/:vaultId`), so the chrome
            // persists across navigation without rebuilding.
          ),
        );
      },
    );
  }
}

// ── AppBar ─────────────────────────────────────────────────────────

class _DetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailAppBar({
    required this.state,
    required this.onBack,
    required this.tabController,
    required this.onImport,
    required this.onExport,
  });

  final VaultDetailState state;
  final VoidCallback onBack;
  final TabController tabController;
  final VoidCallback onImport;
  final VoidCallback onExport;

  static const double _tabBarHeight = 44;

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight + _tabBarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final s = state;
    final loaded = s is VaultDetailLoaded ? s.vault : null;
    final subtitle = loaded != null
        ? l10n.vaultEntryCount(loaded.entryCount)
        : '';
    final onSurface = AppColors.onSurface(brightness);
    final subtle = AppColors.onSurfaceSubtle(brightness);

    return AppBar(
      // Transparent AppBar lets the parent gradient show through —
      // matches the rest of the app's visual language.
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      // Force left-alignment — iOS defaults this AppBar to centered
      // titles, which leaves the vault name floating in the middle of
      // the bar. The list page header is left-aligned, so the detail
      // bar should match.
      centerTitle: false,
      iconTheme: IconThemeData(color: onSurface),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        onPressed: onBack,
      ),
      actions: [
        if (loaded != null)
          PopupMenuButton<_VaultAction>(
            icon: Icon(Icons.more_vert, color: onSurface),
            color: AppColors.modalBackground(brightness),
            onSelected: (action) => switch (action) {
              _VaultAction.import => onImport(),
              _VaultAction.export => onExport(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _VaultAction.import,
                child: _MenuRow(
                  icon: Icons.file_upload_outlined,
                  label: l10n.vaultActionImport,
                ),
              ),
              PopupMenuItem(
                value: _VaultAction.export,
                child: _MenuRow(
                  icon: Icons.file_download_outlined,
                  label: l10n.vaultActionExport,
                ),
              ),
            ],
          ),
      ],
      title: AppBarTitle(
        title: loaded?.name ?? l10n.vaultTitle,
        subtitle: subtitle,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(_tabBarHeight),
        child: SizedBox(
          height: _tabBarHeight,
          child: TabBar(
            controller: tabController,
            // Scrollable so long translated tab labels (e.g. "Ustawienia"
            // in Polish) are not truncated — user can tap or swipe to
            // navigate between tabs.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.cardPadding,
            ),
            labelColor: AppColors.brandRed,
            unselectedLabelColor: subtle,
            indicatorColor: AppColors.brandRed,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 2,
            // Hairline separator below the entire tab row — matches the
            // prototype's `border-bottom: 1px solid rgba(…, 0.06)`.
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
              Tab(text: l10n.vaultTabEntries),
              Tab(text: l10n.vaultTabAgents),
              Tab(text: l10n.vaultTabLogs),
              Tab(text: l10n.vaultTabMembers),
              Tab(text: l10n.vaultTabSettings),
            ],
          ),
        ),
      ),
    );
  }
}

/// Row inside the AppBar overflow menu — icon + label.
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
        const SizedBox(width: AppSpacing.md),
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

// ── Loaded body ────────────────────────────────────────────────────

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.vault,
    required this.tabController,
    required this.grantsRefresh,
    required this.initialFormData,
    required this.onFormChanged,
    required this.onDelete,
    required this.onSave,
  });

  final VaultEntity vault;
  final TabController tabController;
  final int grantsRefresh;
  final VaultFormData? initialFormData;
  final ValueChanged<VaultFormData> onFormChanged;
  final VoidCallback onDelete;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Tab bar → content: fieldGap (canonical segment/tab → next rhythm).
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.fieldGap,
        AppSpacing.screenH,
        0,
      ),
      child: TabBarView(
        controller: tabController,
        children: [
          // Entries are sourced from `EntryListCubit` provided above.
          const VaultEntriesTab(),
          _VaultAgentsTab(key: ValueKey(grantsRefresh), vaultId: vault.id),
          // Logs tab (CVT-121) — vault-scoped audit feed. Horizontal padding
          // and the tab-bar → content gap are owned by the TabBarView wrapper.
          VaultAuditLogTab(
            vaultId: vault.id,
            contentPadding: const EdgeInsets.fromLTRB(
              0,
              0,
              0,
              AppSpacing.listBottom,
            ),
          ),
          _PlaceholderTabBuilder(
            messageKey: (l10n) => l10n.vaultMembersEmpty,
            icon: Icons.group_outlined,
          ),
          if (initialFormData != null)
            VaultSettingsTab(
              vaultId: vault.id,
              initial: initialFormData!,
              onChanged: onFormChanged,
              onDelete: onDelete,
              onSave: onSave,
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _PlaceholderTabBuilder extends StatelessWidget {
  const _PlaceholderTabBuilder({required this.messageKey, required this.icon});

  final String Function(AppLocalizations) messageKey;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return VaultPlaceholderTab(icon: icon, message: messageKey(l10n));
  }
}

/// Agents tab — the vault's grants list (filtered by vaultId), mirroring the web Vault→Agents tab.
/// Horizontal padding is zeroed because the parent TabBarView is already padded.
class _VaultAgentsTab extends StatelessWidget {
  const _VaultAgentsTab({super.key, required this.vaultId});

  final String vaultId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ContextGrantsTab(
      vaultId: vaultId,
      emptyTitle: l10n.vaultAgentsEmptyTitle,
      emptyHint: l10n.vaultAgentsEmptyHint,
      // Tab bar → content gap (fieldGap) is owned by the TabBarView wrapper.
      contentPadding: const EdgeInsets.fromLTRB(0, 0, 0, AppSpacing.listBottom),
    );
  }
}

// ── Loading / error ────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.brandRed),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.kind});

  final VaultErrorKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Text(
          switch (kind) {
            VaultErrorKind.notFound => l10n.vaultErrorNotFound,
            VaultErrorKind.forbidden => l10n.vaultErrorForbidden,
            VaultErrorKind.planLimitReached => l10n.vaultErrorPlanLimitReached,
            VaultErrorKind.fullModeNotAllowed =>
              l10n.vaultErrorFullModeNotAllowed,
            VaultErrorKind.networkError => l10n.errorCannotConnectToServer,
            VaultErrorKind.unknown => l10n.vaultErrorUnknown,
          },
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
