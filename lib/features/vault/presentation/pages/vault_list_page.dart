import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../cubit/vault_list_cubit.dart';
import '../widgets/create_vault_sheet.dart';
import '../widgets/vault_card.dart';

/// Top-level vault list — replaces the post-unlock placeholder home.
///
/// Loads the vault list on mount and supports:
///   * pull-to-refresh
///   * tap-to-detail navigation
///   * "+" FAB → bottom sheet → on success, navigate into the new vault
///   * lock / logout from the app bar
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
  Future<void> _openCreateSheet() async {
    final created = await CreateVaultSheet.show(context);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(l10n.vaultTitle),
        backgroundColor: AppColors.darkSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: l10n.unlockLockVault,
            onPressed: () =>
                context.read<AuthBloc>().add(const VaultLockRequested()),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                context.read<AuthBloc>().add(const AuthLogoutRequested()),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.darkBackgroundGradient,
        ),
        child: SafeArea(
          top: false,
          child: BlocBuilder<VaultListCubit, VaultListState>(
            builder: (context, state) {
              return switch (state) {
                VaultListInitial() || VaultListLoading() => const _LoadingView(),
                VaultListError(:final kind) => _ErrorView(
                    kind: kind,
                    onRetry: () =>
                        context.read<VaultListCubit>().loadVaults(),
                  ),
                VaultListLoaded(:final vaults) => vaults.isEmpty
                    ? _EmptyView(onCreate: _openCreateSheet)
                    : _ListView(
                        onRefresh: () =>
                            context.read<VaultListCubit>().loadVaults(),
                      ),
              };
            },
          ),
        ),
      ),
      floatingActionButton: BlocBuilder<VaultListCubit, VaultListState>(
        builder: (context, state) {
          // Hide the FAB on the empty state — that screen owns its own
          // primary CTA, so a duplicate FAB would compete for attention.
          final showFab = state is VaultListLoaded && state.vaults.isNotEmpty;
          if (!showFab) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            backgroundColor: AppColors.brandRed,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: Text(l10n.vaultNewVault),
            onPressed: _openCreateSheet,
          );
        },
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
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.vaultCreateFirst,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textTertiary,
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
              style: const TextStyle(
                color: AppColors.textPrimary,
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

class _ListView extends StatelessWidget {
  const _ListView({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VaultListCubit, VaultListState>(
      buildWhen: (prev, next) => next is VaultListLoaded,
      builder: (context, state) {
        if (state is! VaultListLoaded) return const SizedBox.shrink();
        return RefreshIndicator(
          color: AppColors.tealAccent,
          backgroundColor: AppColors.darkSurface,
          onRefresh: onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: state.vaults.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, index) {
              final vault = state.vaults[index];
              return VaultCard(
                vault: vault,
                onTap: () => context.push('/vaults/${vault.id}'),
              );
            },
          ),
        );
      },
    );
  }
}
