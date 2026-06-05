import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../cubit/grants_list_cubit.dart';
import '../widgets/grant_card.dart';
import '../widgets/grant_format.dart';

/// Grant-management list for a single vault.
///
/// Reached from the vault detail screen. Lists every grant on the vault
/// with a status filter and cursor-based pagination. Tapping a row pushes
/// the grant detail screen.
class GrantsPage extends StatelessWidget {
  const GrantsPage({super.key, required this.vaultId});

  final String vaultId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<GrantsListCubit>(
      create: (_) =>
          getIt<GrantsListCubit>(param1: vaultId)..load(),
      child: _GrantsView(vaultId: vaultId),
    );
  }
}

/// Status filter options exposed as chips. `null` value = "all".
const _statusFilters = <(String?, String)>[
  (null, 'all'),
  ('pending', 'pending'),
  ('active', 'active'),
  ('revoked', 'revoked'),
];

class _GrantsView extends StatelessWidget {
  const _GrantsView({required this.vaultId});

  final String vaultId;

  String _filterLabel(AppLocalizations l10n, String key) {
    return switch (key) {
      'pending' => l10n.grantStatusPending,
      'active' => l10n.grantStatusActive,
      'revoked' => l10n.grantStatusRevoked,
      _ => l10n.grantsFilterAll,
    };
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
          titleSpacing: 0,
          iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
          title: Text(
            l10n.grantsScreenTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: BlocListener<GrantsListCubit, GrantsListState>(
            listenWhen: (prev, curr) =>
                prev.mutationError != curr.mutationError &&
                curr.mutationError != null,
            listener: (context, state) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(grantsErrorMessage(l10n, state.mutationError!)),
                ));
              context.read<GrantsListCubit>().acknowledgeMutationError();
            },
            child: Column(
              children: [
                _FilterRow(filterLabel: _filterLabel),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.brandRed,
                    backgroundColor: AppColors.cardSurface(brightness),
                    onRefresh: () => context.read<GrantsListCubit>().load(),
                    child: BlocBuilder<GrantsListCubit, GrantsListState>(
                      builder: (context, state) => _Body(state: state),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.filterLabel});

  final String Function(AppLocalizations, String) filterLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocBuilder<GrantsListCubit, GrantsListState>(
      buildWhen: (prev, curr) => prev.statusFilter != curr.statusFilter,
      builder: (context, state) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              for (final (value, key) in _statusFilters) ...[
                _FilterChip(
                  label: filterLabel(l10n, key),
                  selected: state.statusFilter == value,
                  onTap: () =>
                      context.read<GrantsListCubit>().setStatusFilter(value),
                  brightness: brightness,
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.brightness,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brandRed.withValues(alpha: 0.15)
                : AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.brandRed
                  : AppColors.cardBorder(brightness),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? AppColors.brandRed
                  : AppColors.onSurfaceMuted(brightness),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final GrantsListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return switch (state.status) {
      GrantsListStatus.initial ||
      GrantsListStatus.loading =>
        const _GrantsSkeleton(),
      GrantsListStatus.error => _GrantsError(
          message: grantsErrorMessage(l10n, state.error!),
          onRetry: () => context.read<GrantsListCubit>().load(),
        ),
      GrantsListStatus.loaded => _GrantsList(state: state),
    };
  }
}

class _GrantsList extends StatefulWidget {
  const _GrantsList({required this.state});

  final GrantsListState state;

  @override
  State<_GrantsList> createState() => _GrantsListState();
}

class _GrantsListState extends State<_GrantsList> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_controller.position.pixels >=
        _controller.position.maxScrollExtent - 240) {
      context.read<GrantsListCubit>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final grants = widget.state.grants;

    if (grants.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [_GrantsEmpty()],
      );
    }

    return ListView.separated(
      controller: _controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      itemCount: grants.length + (widget.state.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        if (index >= grants.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brandRed,
                ),
              ),
            ),
          );
        }
        final grant = grants[index];
        return GrantCard(
          grant: grant,
          onTap: () => context.push(
            '/vaults/${grant.vaultId}/grants/${grant.id}',
          ),
        );
      },
    );
  }
}

class _GrantsEmpty extends StatelessWidget {
  const _GrantsEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
          Icon(
            Icons.key_outlined,
            size: 32,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.grantsEmpty,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.grantsEmptyHint,
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

class _GrantsSkeleton extends StatelessWidget {
  const _GrantsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SkeletonBox(
            height: 64,
            delay: Duration(milliseconds: i * 80),
          ),
        ),
      ),
    );
  }
}

class _GrantsError extends StatelessWidget {
  const _GrantsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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
                child: Text(l10n.grantsRetry),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
