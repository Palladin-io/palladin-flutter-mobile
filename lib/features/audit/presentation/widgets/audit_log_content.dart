import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../../domain/exceptions/audit_exceptions.dart';
import '../audit_log_format.dart';
import '../cubit/audit_log_cubit.dart';
import 'audit_log_filter_sheet.dart';
import 'audit_log_row.dart';

/// Shared body for the vault-scoped Logs tab (CVT-121) and the org-wide Logs
/// screen (CVT-66).
///
/// Renders the search bar (with a `tune` filter trigger that opens the filter
/// sheet — event-type groups, user, agent, vault and date range) and the
/// paginated, expandable [AuditLogRow] list with skeleton / error / empty
/// states. Reads its [AuditLogCubit] from the nearest provider — the host
/// (tab / page) owns creation and chrome.
class AuditLogContent extends StatefulWidget {
  const AuditLogContent({
    super.key,
    required this.groups,
    required this.showVaultFilter,
    this.contentPadding = const EdgeInsets.fromLTRB(
      0,
      0,
      0,
      AppSpacing.listBottom,
    ),
  });

  /// Event groups offered for selection in the filter sheet.
  final List<AuditEventGroup> groups;

  /// Whether to show the vault dropdown in the filter sheet (org scope).
  final bool showVaultFilter;

  /// Outer padding; the horizontal value gutters the search bar and list.
  final EdgeInsets contentPadding;

  @override
  State<AuditLogContent> createState() => _AuditLogContentState();
}

class _AuditLogContentState extends State<AuditLogContent> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters(AuditLogState state) async {
    final cubit = context.read<AuditLogCubit>();
    final result = await AuditLogFilterSheet.show(
      context,
      initial: state.filter,
      groups: widget.groups,
      agents: state.agentOptions,
      users: state.userOptions,
      vaults: widget.showVaultFilter ? state.vaultOptions : null,
    );
    if (result == null) return;
    cubit.applyFilter(result);
  }

  bool _onScrollEnd(ScrollEndNotification notification) {
    final metrics = notification.metrics;
    if (metrics.pixels >= metrics.maxScrollExtent - 240) {
      context.read<AuditLogCubit>().loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final hPad = widget.contentPadding.left;

    return BlocBuilder<AuditLogCubit, AuditLogState>(
      builder: (context, state) {
        return NotificationListener<ScrollEndNotification>(
          onNotification: _onScrollEnd,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  hPad,
                  widget.contentPadding.top,
                  hPad,
                  AppSpacing.fieldGap,
                ),
                sliver: SliverToBoxAdapter(
                  child: AppSearchField(
                    controller: _searchController,
                    hint: l10n.auditSearchHint,
                    filterActive: state.hasActiveFilters,
                    onChanged: (q) => context.read<AuditLogCubit>().search(q),
                    onToggleFilter: () => _openFilters(state),
                  ),
                ),
              ),
              ..._contentSlivers(context, state, l10n, brightness, hPad),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _contentSlivers(
    BuildContext context,
    AuditLogState state,
    AppLocalizations l10n,
    Brightness brightness,
    double hPad,
  ) {
    switch (state.status) {
      case AuditLogStatus.initial:
      case AuditLogStatus.loading:
        return [
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            sliver: SliverList.separated(
              itemCount: 6,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.cardGap),
              itemBuilder: (_, i) => SkeletonBox(
                height: 64,
                delay: Duration(milliseconds: i * 80),
              ),
            ),
          ),
        ];
      case AuditLogStatus.error:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _ErrorState(
              message: auditErrorMessage(
                l10n,
                state.error ?? AuditErrorKind.unknown,
              ),
              brightness: brightness,
              onRetry: () => context.read<AuditLogCubit>().reload(),
            ),
          ),
        ];
      case AuditLogStatus.loaded:
        final items = state.filtered;
        if (items.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                title: state.hasActiveFilters || state.query.isNotEmpty
                    ? l10n.auditEmptyFilteredTitle
                    : l10n.auditEmptyTitle,
                hint: state.hasActiveFilters || state.query.isNotEmpty
                    ? l10n.auditEmptyFilteredHint
                    : l10n.auditEmptyHint,
                brightness: brightness,
              ),
            ),
          ];
        }
        return [
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.cardGap),
              itemBuilder: (_, i) =>
                  AuditLogRow(entry: items[i], agentNames: state.agentNames),
            ),
          ),
          SliverToBoxAdapter(
            child: _PaginationFooter(
              state: state,
              brightness: brightness,
              horizontalPadding: hPad,
              bottomPadding: widget.contentPadding.bottom,
              onRetry: () => context.read<AuditLogCubit>().loadMore(),
            ),
          ),
        ];
    }
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.state,
    required this.brightness,
    required this.horizontalPadding,
    required this.bottomPadding,
    required this.onRetry,
  });

  final AuditLogState state;
  final Brightness brightness;

  /// Horizontal gutter — must match the list/search sliver `hPad` so the footer
  /// aligns with the rows. The host owns the gutter via `contentPadding` (e.g.
  /// VaultDetailPage passes 0 because the TabBarView already insets 20px).
  final double horizontalPadding;
  final double bottomPadding;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (state.nextCursor == null) {
      return SizedBox(height: bottomPadding);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        AppSpacing.section,
        horizontalPadding,
        bottomPadding,
      ),
      child: state.loadMoreError
          ? Column(
              children: [
                Text(
                  l10n.auditLoadMoreError,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.brandRed,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: AppSpacing.innerGap),
                TextButton(onPressed: onRetry, child: Text(l10n.vaultRetry)),
              ],
            )
          : const Center(
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.hint,
    required this.brightness,
  });

  final String title;
  final String hint;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 40,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.brightness,
    required this.onRetry,
  });

  final String message;
  final Brightness brightness;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(onPressed: onRetry, child: Text(l10n.vaultRetry)),
        ],
      ),
    );
  }
}
