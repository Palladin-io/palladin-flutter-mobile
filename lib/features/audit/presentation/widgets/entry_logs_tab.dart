import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/exceptions/audit_exceptions.dart';
import '../audit_log_format.dart';
import '../cubit/entry_logs_cubit.dart';
import 'audit_log_row.dart';
import 'entry_logs_filter_sheet.dart';

/// The entry-detail **Logs** tab (CVT-133).
///
/// Read-only, filterable audit feed scoped to a single entry: a search bar
/// with a `tune` filter trigger, a filter sheet (event-type checkboxes +
/// agent dropdown + date range) and expandable [AuditLogRow]s. Provides its
/// own [EntryLogsCubit] scoped to the given vault/entry.
class EntryLogsTab extends StatelessWidget {
  const EntryLogsTab({
    super.key,
    required this.vaultId,
    required this.entryId,
    required this.active,
    this.cubit,
    this.contentPadding = const EdgeInsets.fromLTRB(
      AppSpacing.screenH,
      AppSpacing.fieldGap,
      AppSpacing.screenH,
      AppSpacing.listBottom,
    ),
  });

  final String vaultId;
  final String entryId;
  final bool active;
  final EntryLogsCubit? cubit;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<EntryLogsCubit>(
      create: (_) =>
          cubit ?? getIt<EntryLogsCubit>(param1: vaultId, param2: entryId),
      child: _EntryLogsView(contentPadding: contentPadding, active: active),
    );
  }
}

class _EntryLogsView extends StatefulWidget {
  const _EntryLogsView({required this.contentPadding, required this.active});

  final EdgeInsets contentPadding;
  final bool active;

  @override
  State<_EntryLogsView> createState() => _EntryLogsViewState();
}

class _EntryLogsViewState extends State<_EntryLogsView> {
  final _searchController = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadWhenActive();
  }

  @override
  void didUpdateWidget(_EntryLogsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadWhenActive();
  }

  void _loadWhenActive() {
    if (widget.active && !_loaded) {
      _loaded = true;
      context.read<EntryLogsCubit>().load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters(BuildContext context, EntryLogsState state) async {
    final cubit = context.read<EntryLogsCubit>();
    final result = await EntryLogsFilterSheet.show(
      context,
      initial: EntryLogsFilter(
        eventTypes: state.eventTypeFilter,
        agentId: state.agentFilter,
        fromDate: state.fromDate,
        toDate: state.toDate,
      ),
      agents: state.agentOptions,
    );
    if (result == null) return;
    cubit.applyFilters(
      eventTypes: result.eventTypes,
      agentId: result.agentId,
      from: result.fromDate,
      to: result.toDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final hPad = widget.contentPadding.left;

    return BlocBuilder<EntryLogsCubit, EntryLogsState>(
      builder: (context, state) {
        return CustomScrollView(
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
                  onChanged: (q) => context.read<EntryLogsCubit>().search(q),
                  onToggleFilter: () => _openFilters(context, state),
                ),
              ),
            ),
            ..._contentSlivers(context, state, l10n, brightness, hPad),
          ],
        );
      },
    );
  }

  List<Widget> _contentSlivers(
    BuildContext context,
    EntryLogsState state,
    AppLocalizations l10n,
    Brightness brightness,
    double hPad,
  ) {
    switch (state.status) {
      case EntryLogsStatus.initial:
      case EntryLogsStatus.loading:
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xxxl),
                child: CircularProgressIndicator(color: AppColors.brandRed),
              ),
            ),
          ),
        ];
      case EntryLogsStatus.error:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _ErrorState(
              message: auditErrorMessage(
                l10n,
                state.error ?? AuditErrorKind.unknown,
              ),
              brightness: brightness,
              onRetry: () => context.read<EntryLogsCubit>().reload(),
            ),
          ),
        ];
      case EntryLogsStatus.loaded:
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
          if (state.nextCursor != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                hPad,
                AppSpacing.section,
                hPad,
                widget.contentPadding.bottom,
              ),
              sliver: SliverToBoxAdapter(
                child: _LoadMoreButton(
                  loading: state.loadingMore,
                  hasError: state.loadMoreError,
                  onPressed: () => context.read<EntryLogsCubit>().loadMore(),
                  brightness: brightness,
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: SizedBox(height: widget.contentPadding.bottom),
            ),
        ];
    }
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.loading,
    required this.hasError,
    required this.onPressed,
    required this.brightness,
  });

  final bool loading;
  final bool hasError;
  final VoidCallback onPressed;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasError) ...[
          Text(
            l10n.auditLoadMoreError,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.brandRed, fontSize: 11),
          ),
          const SizedBox(height: AppSpacing.innerGap),
        ],
        SizedBox(
          height: AppSpacing.controlHeight,
          child: OutlinedButton(
            onPressed: loading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: hasError
                  ? AppColors.brandRed
                  : AppColors.onSurfaceMuted(brightness),
              side: BorderSide(
                color: hasError
                    ? AppColors.brandRed.withValues(alpha: 0.5)
                    : AppColors.cardBorder(brightness),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brandRed,
                    ),
                  )
                : Text(
                    hasError ? l10n.vaultRetry : l10n.auditLoadMore,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
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
