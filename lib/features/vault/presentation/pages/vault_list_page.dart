import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/widgets/app_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../shell/presentation/pages/app_shell.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../cubit/vault_list_cubit.dart';
import '../widgets/create_vault_sheet.dart';
import '../widgets/vault_card.dart';
import '../widgets/vault_library_switch.dart';
import 'global_entries_page.dart';

/// Top-level vault list — replaces the post-unlock placeholder home.
///
/// Loads the vault list on mount and supports:
///   * pull-to-refresh,
///   * tap-to-detail navigation,
///   * floating "+" action → bottom sheet → on success, navigate into
///     the new vault (matches the FAB style used inside the vault
///     detail entries/agents tabs),
///   * local name search across the loaded list.
///
/// Settings (lock / log out / account) are reachable from the bottom
/// navigation's Settings tab, which opens the shell-owned
/// [SettingsDrawer] — the header therefore no longer duplicates a cog
/// icon of its own.
class VaultListPage extends StatefulWidget {
  static const pageKey = ValueKey('vault-library');
  const VaultListPage({super.key, this.entries = false});
  final bool entries;

  @override
  State<VaultListPage> createState() => _VaultListPageState();
}

class _VaultListPageState extends State<VaultListPage> {
  late final VaultListCubit _cubit;
  late final AuthBloc _authBloc;

  @override
  void initState() {
    super.initState();
    // Cache the provider while this element is active. Vaults remains below a
    // pushed Vault Detail route and can be deactivated before it is disposed;
    // looking the provider up from dispose() is therefore unsafe.
    _authBloc = context.read<AuthBloc>();
    final auth = _authBloc.state;
    final privateKey = auth is AuthAuthenticated ? auth.privateKey : null;
    _cubit = getIt<VaultListCubit>()..loadIfNeeded(privateKey);
  }

  @override
  void dispose() {
    final auth = _authBloc.state;
    if (auth is! AuthAuthenticated || auth.isVaultLocked) _cubit.lock();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (_, state) {
        if (state is! AuthAuthenticated || state.isVaultLocked) _cubit.lock();
      },
      child: BlocProvider<VaultListCubit>.value(
        value: _cubit,
        child: _VaultListView(entries: widget.entries),
      ),
    );
  }
}

class _VaultListView extends StatefulWidget {
  const _VaultListView({required this.entries});
  final bool entries;

  @override
  State<_VaultListView> createState() => _VaultListViewState();
}

class _VaultListViewState extends State<_VaultListView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  final _entriesPreferences = GlobalEntriesPreferences();
  late final StreamSubscription<AuthState> _authChanges;

  /// Cached FAB widget — reused across rebuilds so [FabRegistrar] does
  /// not see a new object each build and re-register in a loop, which
  /// would otherwise overwrite a sibling page's FAB.
  Widget? _cachedFab;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text.trim();
      if (next == _query) return;
      setState(() => _query = next);
    });
    _authChanges = context.read<AuthBloc>().stream.listen((state) {
      if (state is! AuthAuthenticated || state.isVaultLocked) {
        _searchController.clear();
        _entriesPreferences.clear();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_authChanges.cancel());
    _searchController.dispose();
    _entriesPreferences.dispose();
    super.dispose();
  }

  /// Wraps a `showModalBottomSheet` call with shell-level bottom-nav
  /// hiding so the persistent nav doesn't bleed up into the sheet.
  /// All sheet entry points on this page must funnel through here.
  ///
  /// The shell now animates the nav in/out via `AnimatedSlide`, so the
  /// reveal call fires immediately when the sheet starts dismissing —
  /// both animations run in parallel and the nav slides up at the same
  /// pace the sheet slides down.
  Future<T?> _withBottomNavHidden<T>(Future<T?> Function() open) async {
    final shell = AppShellScope.of(context);
    shell.setBottomNavHidden(true);
    try {
      return await open();
    } finally {
      shell.setBottomNavHidden(false);
    }
  }

  Future<void> _openCreateSheet() async {
    final created = await _withBottomNavHidden<VaultEntity>(
      () => CreateVaultSheet.show(context),
    );
    if (!mounted) return;
    if (created == null) return;
    final auth = context.read<AuthBloc>().state;
    final privateKey = auth is AuthAuthenticated ? auth.privateKey : null;
    await context.read<VaultListCubit>().loadVaults(privateKey);
    if (!mounted) return;
    context.push('/vaults/${created.id}');
  }

  /// Decide whether tapping "+" opens the create sheet or the premium-gate
  /// sheet. Mirrors web: the first vault is always free; further vaults need
  /// the `multipleVaults` permission. Backend currently grants it to everyone
  /// (MaxValue), so creation is unblocked — the gate fires only once real
  /// billing roles withhold the bit.
  Future<void> _onAddTapped() async {
    final state = context.read<VaultListCubit>().state;
    final vaultCount = state is VaultListLoaded ? state.vaults.length : 0;
    final auth = context.read<AuthBloc>().state;
    final permissions = auth is AuthAuthenticated ? auth.permissions : 0;
    final canCreateMore =
        vaultCount == 0 || (permissions & Permissions.multipleVaults) != 0;
    if (!canCreateMore) {
      await _showPremiumSheet(reason: 'vaults');
      return;
    }
    await _openCreateSheet();
  }

  /// Surface the premium-gate bottom sheet and track the paywall
  /// impression. [reason] is the identifier of the limit that triggered
  /// the gate (e.g. `vaults`, `entries`, `agents`) — kept open so future
  /// callers can wire other paywalls into the same analytics funnel.
  Future<void> _showPremiumSheet({required String reason}) async {
    AnalyticsService.instance.capture(
      'billing',
      'paywall-shown',
      properties: {'reason': reason},
    );
    await _withBottomNavHidden<void>(
      () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: (_) => _PremiumGateSheet(reason: reason),
      ),
    );
  }

  List<VaultEntity> _filter(List<VaultEntity> vaults) {
    if (_query.isEmpty) return vaults;
    final needle = _query.toLowerCase();
    return vaults
        .where((v) => v.name.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  Future<void> _refresh() {
    final auth = context.read<AuthBloc>().state;
    return context.read<VaultListCubit>().loadVaults(
      auth is AuthAuthenticated ? auth.privateKey : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.entries) {
      return GlobalEntriesPage(preferences: _entriesPreferences);
    }
    final fab = _cachedFab ??= AppFab.shell(
      onPressed: _onAddTapped,
      tooltip: l10n.vaultNewVault,
    );
    return BlocBuilder<VaultListCubit, VaultListState>(
      builder: (context, state) {
        final vaults = state is VaultListLoaded
            ? state.vaults
            : <VaultEntity>[];
        final filtered = _filter(vaults);
        return AppScreen.titled(
          title: l10n.vaultListTitle,
          actions: const [VaultLibrarySwitch(entries: false)],
          subtitle: l10n.vaultListSummary(
            vaults.length,
            vaults.fold<int>(0, (sum, vault) => sum + vault.entryCount),
          ),
          floatingActionButton: FabRegistrar(fab: fab),
          body: RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.brandRed,
            child: CustomScrollView(
              key: const PageStorageKey('vault-library-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    0,
                    AppSpacing.screenH,
                    AppSpacing.fieldGap,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: AppSearchField(
                      controller: _searchController,
                      hint: l10n.vaultSearchHint,
                    ),
                  ),
                ),
                if (state is VaultListInitial || state is VaultListLoading)
                  SliverToBoxAdapter(
                    child: _SkeletonList(
                      brightness: Theme.of(context).brightness,
                    ),
                  )
                else if (state is VaultListError ||
                    state is VaultListResetRequired)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorView(
                      kind: state is VaultListError
                          ? state.kind
                          : VaultErrorKind.unknown,
                      onRetry: _refresh,
                    ),
                  )
                else if (state is VaultListLoaded && vaults.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyView(onCreate: _openCreateSheet),
                  )
                else if (state is VaultListLoaded && filtered.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _SearchEmptyView(),
                  )
                else if (state is VaultListLoaded)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      0,
                      AppSpacing.screenH,
                      AppSpacing.listBottom,
                    ),
                    sliver: SliverList.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.cardGap),
                      itemBuilder: (_, index) => VaultCard(
                        vault: filtered[index],
                        onTap: () async {
                          await context.push('/vaults/${filtered[index].id}');
                          if (mounted) await _refresh();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SearchEmptyView extends StatelessWidget {
  const _SearchEmptyView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.screenBottom,
      ),
      child: Center(
        child: Text(
          l10n.vaultSearchEmpty,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet shown when the user taps the header "+" while they've
/// already hit the free-plan single-vault limit.
///
/// Background and shape mirror [CreateVaultSheet] one-for-one so both
/// sheets feel like siblings. The amber `workspace_premium` glyph sits
/// on its own (no tinted container) and the CTA matches the prototype's
/// `.btn` recipe (full width, 8px radius, 13px/600). The CTA is wired
/// to the future billing route — for now it just dismisses the sheet
/// and leaves a TODO for the monetization phase.
class _PremiumGateSheet extends StatelessWidget {
  const _PremiumGateSheet({required this.reason});

  /// Identifier of the limit that triggered the gate (`vaults`,
  /// `entries`, `agents`, …). Carried through so future analytics on
  /// this sheet can attribute taps back to the originating paywall.
  // ignore: unused_field
  final String reason;

  void _onUpgradeTapped(BuildContext context) {
    Navigator.of(context).pop();
    // TODO(billing): navigate to billing screen once /billing route exists
    // The upgrade action is intentionally unavailable until billing ships.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final premium = AppColors.premium(brightness);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        // Use the device's physical bottom inset (not Scaffold-adjusted)
        // so the sheet hugs the home indicator instead of floating above
        // the shell-reserved bottom-nav space.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.md,
            AppSpacing.screenH,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.onSurfaceSubtle(
                      brightness,
                    ).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Center(
                child: Icon(Icons.workspace_premium, color: premium, size: 32),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.premiumGateTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: AppSpacing.innerGap),
              Text(
                l10n.premiumGateSubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              // Amber outline CTA — mirrors the web panel's premium
              // button (transparent fill with low-alpha tint, amber
              // border and label) instead of the previous solid amber
              // ElevatedButton, so the upgrade affordance reads as a
              // distinct premium accent rather than a stock primary.
              OutlinedButton.icon(
                onPressed: () => _onUpgradeTapped(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: premium,
                  backgroundColor: premium.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: premium.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.cardPadding,
                    horizontal: AppSpacing.lg,
                  ),
                ),
                icon: const Icon(Icons.workspace_premium, size: 15),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.premiumGateCta,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.chipGap),
                    const Icon(Icons.arrow_forward, size: 14),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.innerGap),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.onSurfaceSubtle(brightness),
                  minimumSize: const Size(double.infinity, 44),
                ),
                child: Text(
                  l10n.premiumGateDismiss,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList({required this.brightness});
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Header→content gap (headerGap) is owned by the header above.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        0,
      ),
      child: Column(
        children: List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
            child: const SkeletonBox(height: 84),
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenH,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.brandRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.shield_outlined,
                color: AppColors.brandRed,
                size: 36,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              l10n.vaultNoVaults,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.innerGap),
            Text(
              l10n.vaultCreateFirst,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandRed,
                  foregroundColor: AppColors.onBrandRed,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: Text(
                  l10n.vaultNewVault,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: onCreate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.kind, required this.onRetry});

  final VaultErrorKind kind;
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
            const Icon(
              Icons.error_outline,
              color: AppColors.brandRed,
              size: 40,
            ),
            const SizedBox(height: AppSpacing.section),
            Text(
              _errorMessage(context, kind),
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
              style: TextButton.styleFrom(foregroundColor: AppColors.brandRed),
              child: Text(l10n.vaultRetry),
            ),
          ],
        ),
      ),
    );
  }

  String _errorMessage(BuildContext context, VaultErrorKind kind) {
    final l10n = AppLocalizations.of(context)!;
    return switch (kind) {
      VaultErrorKind.notFound => l10n.vaultErrorNotFound,
      VaultErrorKind.forbidden => l10n.vaultErrorForbidden,
      VaultErrorKind.planLimitReached => l10n.vaultErrorPlanLimitReached,
      VaultErrorKind.fullModeNotAllowed => l10n.vaultErrorFullModeNotAllowed,
      VaultErrorKind.networkError => l10n.errorCannotConnectToServer,
      VaultErrorKind.conflict => l10n.vaultMetadataConflict,
      VaultErrorKind.corrupt => l10n.vaultMetadataCorrupt,
      VaultErrorKind.unknown => l10n.vaultErrorUnknown,
    };
  }
}
