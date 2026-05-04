import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../shell/presentation/pages/app_shell.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../cubit/vault_list_cubit.dart';
import '../widgets/create_vault_sheet.dart';
import '../widgets/vault_card.dart';

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
class VaultListPage extends StatelessWidget {
  const VaultListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VaultListCubit>(
      create: (_) => getIt<VaultListCubit>()..loadVaults(),
      child: const _VaultListView(),
    );
  }
}

class _VaultListView extends StatefulWidget {
  const _VaultListView();

  @override
  State<_VaultListView> createState() => _VaultListViewState();
}

class _VaultListViewState extends State<_VaultListView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text.trim();
      if (next == _query) return;
      setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    // Refresh first so the back-nav from the detail page lands on a
    // list that actually contains the freshly created vault. Use the
    // State's own `context` (guarded by `mounted` checks) instead of
    // a captured argument so the analyzer is happy across the gap.
    await context.read<VaultListCubit>().loadVaults();
    if (!mounted) return;
    context.push('/vaults/${created.id}');
  }

  /// Decide whether tapping the header "+" should open the create sheet
  /// or the premium-gate bottom sheet. The gate is currently driven by
  /// `vaults.length >= 1` because the backend temporarily issues
  /// `(Permission)int.MaxValue` to every user, so the
  /// `PERMISSION_MULTIPLE_VAULTS` bit is always set and a real
  /// permissions check would never fire.
  ///
  // TODO: replace with permissions gate when backend assigns proper roles
  Future<void> _onAddTapped() async {
    final state = context.read<VaultListCubit>().state;
    final vaultCount =
        state is VaultListLoaded ? state.vaults.length : 0;
    if (vaultCount >= 1) {
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
        body: Stack(
          children: [
            SafeArea(
              child: BlocBuilder<VaultListCubit, VaultListState>(
                builder: (context, state) {
                  return switch (state) {
                    VaultListInitial() ||
                    VaultListLoading() =>
                      const _LoadingView(),
                    VaultListError(:final kind) => _ErrorView(
                        kind: kind,
                        onRetry: () =>
                            context.read<VaultListCubit>().loadVaults(),
                      ),
                    VaultListLoaded(:final vaults) => _LoadedView(
                        vaults: vaults,
                        filtered: _filter(vaults),
                        searchController: _searchController,
                        onCreate: _openCreateSheet,
                        onRefresh: () =>
                            context.read<VaultListCubit>().loadVaults(),
                      ),
                  };
                },
              ),
            ),
            // Hoists the FAB to the shell's [Scaffold] so it stays
            // pinned across page transitions instead of animating with
            // this page's body. Renders 0×0 — purely a side-effect
            // widget.
            Positioned(
              width: 0,
              height: 0,
              child: FabRegistrar(
                fab: Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 4),
                  child: AppFab(
                    onPressed: _onAddTapped,
                    tooltip: l10n.vaultNewVault,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadedView extends StatelessWidget {
  const _LoadedView({
    required this.vaults,
    required this.filtered,
    required this.searchController,
    required this.onCreate,
    required this.onRefresh,
  });

  final List<VaultEntity> vaults;
  final List<VaultEntity> filtered;
  final TextEditingController searchController;
  final VoidCallback onCreate;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final totalEntries = vaults.fold<int>(0, (acc, v) => acc + v.entryCount);

    if (vaults.isEmpty) {
      // Show the same header chrome on the empty state so the screen
      // doesn't lose its identity — but the body is the existing
      // empty-state CTA card.
      return Column(
        children: [
          const _HeaderRow(vaultCount: 0, entryCount: 0),
          Expanded(child: _EmptyView(onCreate: onCreate)),
        ],
      );
    }

    return RefreshIndicator(
      color: AppColors.tealAccent,
      backgroundColor: AppColors.cardSurface(brightness),
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _HeaderRow(
              vaultCount: vaults.length,
              entryCount: totalEntries,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: AppSearchField(
                controller: searchController,
                hint: AppLocalizations.of(context)!.vaultSearchHint,
              ),
            ),
          ),
          if (filtered.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _SearchEmptyView(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final vault = filtered[index];
                  final cubit = context.read<VaultListCubit>();
                  return VaultCard(
                    vault: vault,
                    onTap: () async {
                      await context.push('/vaults/${vault.id}');
                      // Refresh list after returning from detail so any
                      // name/icon/color edits are reflected immediately.
                      if (context.mounted) cubit.loadVaults();
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom header that replaces the AppBar — title + summary on the
/// left, no trailing chrome. The "+" affordance now lives in the
/// floating action button and Settings is reachable from the bottom
/// navigation, so the header no longer duplicates either.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.vaultCount,
    required this.entryCount,
  });

  final int vaultCount;
  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.vaultListTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.vaultListSummary(vaultCount, entryCount),
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
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
    // For now, no-op — tracked in Linear as part of Phase 4 monetization
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
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.onSurfaceSubtle(brightness)
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Icon(
                  Icons.workspace_premium,
                  color: premium,
                  size: 32,
                ),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 8),
              Text(
                l10n.premiumGateSubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
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
                    vertical: 14,
                    horizontal: 16,
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
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward, size: 14),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.tealAccent),
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
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.tealAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.shield_outlined,
                color: AppColors.tealAccent,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.vaultNoVaults,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.vaultCreateFirst,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandRed,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: Text(
                  l10n.vaultNewVault,
                  style: const TextStyle(
                    fontSize: 15,
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
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.brandRed,
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage(context, kind),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.tealAccent,
              ),
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
      VaultErrorKind.unknown => l10n.vaultErrorUnknown,
    };
  }
}
