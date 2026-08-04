import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/member_index_entry.dart';
import '../../data/services/canonical_entry_detail_service.dart';
import '../cubit/entry_archive_cubit.dart';
import '../widgets/vault_visuals.dart';
import 'recently_deleted_page.dart';

/// Dedicated runtime-only Archive surface for one Vault.
class EntryArchivePage extends StatefulWidget {
  const EntryArchivePage({super.key, required this.vaultId});

  final String vaultId;

  static Future<void> push(BuildContext context, String vaultId) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => BlocProvider<EntryArchiveCubit>(
            create: (_) =>
                getIt<EntryArchiveCubit>(param1: vaultId)..loadLocal(),
            child: EntryArchivePage(vaultId: vaultId),
          ),
        ),
      );

  @override
  State<EntryArchivePage> createState() => _EntryArchivePageState();
}

class _EntryArchivePageState extends State<EntryArchivePage> {
  final TextEditingController _search = TextEditingController();
  bool _filtersVisible = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _restore(MemberIndexEntry entry) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated ||
        auth.isVaultLocked ||
        auth.privateKey == null) {
      context.read<EntryArchiveCubit>().lock();
      return;
    }
    final key = Uint8List.fromList(auth.privateKey!);
    try {
      await context.read<EntryArchiveCubit>().restore(
        entryId: entry.entryId,
        memberPrivateKey: key,
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (_, state) =>
          state is! AuthAuthenticated || state.isVaultLocked,
      listener: (_, _) => context.read<EntryArchiveCubit>().lock(),
      child: AppScreen.appBar(
        appBar: AppBar(
          titleSpacing: 0,
          centerTitle: false,
          title: AppBarTitle(
            title: l10n.entryArchiveTitle,
            subtitle: l10n.entryArchiveSubtitle,
          ),
          actions: [
            IconButton(
              tooltip: l10n.entryDeletedTitle,
              onPressed: () =>
                  RecentlyDeletedPage.push(context, widget.vaultId),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: BlocConsumer<EntryArchiveCubit, EntryArchiveState>(
          listenWhen: (previous, next) =>
              next is EntryArchiveLoaded &&
              next.transientError != null &&
              (previous is! EntryArchiveLoaded ||
                  previous.transientErrorTick != next.transientErrorTick),
          listener: (context, state) {
            final loaded = state as EntryArchiveLoaded;
            final message = switch (loaded.transientError!) {
              CanonicalEntryDetailError.conflict => l10n.entryArchiveConflict,
              CanonicalEntryDetailError.forbidden => l10n.entryErrorForbidden,
              CanonicalEntryDetailError.notFound => l10n.entryErrorNotFound,
              CanonicalEntryDetailError.network => l10n.entryErrorUnknown,
              CanonicalEntryDetailError.corrupt => l10n.entryCorruptProjection,
            };
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          },
          builder: (context, state) => Padding(
            padding: AppScreen.screenPadding,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.fieldGap),
                    child: AppSearchField(
                      controller: _search,
                      hint: l10n.entryArchiveSearchHint,
                      onChanged: context.read<EntryArchiveCubit>().search,
                      filterActive: _filtersVisible,
                      onToggleFilter: () =>
                          setState(() => _filtersVisible = !_filtersVisible),
                    ),
                  ),
                ),
                if (_filtersVisible && state is EntryArchiveLoaded)
                  SliverToBoxAdapter(child: _ArchiveFilters(state: state)),
                ..._content(state, l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(EntryArchiveState state, AppLocalizations l10n) =>
      switch (state) {
        EntryArchiveInitial() => const [
          SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.brandRed),
            ),
          ),
        ],
        EntryArchiveLocked() => [
          SliverFillRemaining(
            child: _ArchiveMessage(text: l10n.entryHistoryLocked),
          ),
        ],
        EntryArchiveError() => [
          SliverFillRemaining(
            child: _ArchiveMessage(text: l10n.entryCorruptProjection),
          ),
        ],
        EntryArchiveLoaded(:final visibleEntries, :final restoringIds) =>
          visibleEntries.isEmpty
              ? [
                  SliverFillRemaining(
                    child: _ArchiveMessage(text: l10n.entryArchiveEmpty),
                  ),
                ]
              : [
                  SliverPadding(
                    padding: const EdgeInsets.only(
                      bottom: AppSpacing.listBottom,
                    ),
                    sliver: SliverList.separated(
                      itemCount: visibleEntries.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.cardGap),
                      itemBuilder: (_, index) {
                        final entry = visibleEntries[index];
                        return _ArchiveRow(
                          entry: entry,
                          restoring: restoringIds.contains(entry.entryId),
                          onRestore: () => _restore(entry),
                        );
                      },
                    ),
                  ),
                ],
      };
}

class _ArchiveFilters extends StatelessWidget {
  const _ArchiveFilters({required this.state});

  final EntryArchiveLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<EntryArchiveCubit>();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.fieldGap),
      child: Wrap(
        spacing: AppSpacing.chipGap,
        runSpacing: AppSpacing.chipGap,
        children: [
          for (final option in <(int?, String)>[
            (null, l10n.entryArchiveAllTypes),
            (EntryType.key.toWire(), l10n.entryTypeKey),
            (EntryType.credential.toWire(), l10n.entryTypeCredential),
            (EntryType.script.toWire(), l10n.entryTypeScript),
            (EntryType.creditCard.toWire(), l10n.entryTypeCreditCard),
          ])
            ChoiceChip(
              selected: state.typeFilter == option.$1,
              label: Text(option.$2),
              onSelected: (_) => cubit.filterType(option.$1),
            ),
          for (final option in <(EntryArchiveSort, String)>[
            (EntryArchiveSort.labelAscending, l10n.entryArchiveSortAscending),
            (EntryArchiveSort.labelDescending, l10n.entryArchiveSortDescending),
            (EntryArchiveSort.typeThenLabel, l10n.entryArchiveSortType),
          ])
            ChoiceChip(
              selected: state.sort == option.$1,
              label: Text(option.$2),
              onSelected: (_) => cubit.sortBy(option.$1),
            ),
        ],
      ),
    );
  }
}

class _ArchiveRow extends StatelessWidget {
  const _ArchiveRow({
    required this.entry,
    required this.restoring,
    required this.onRestore,
  });

  final MemberIndexEntry entry;
  final bool restoring;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final l10n = AppLocalizations.of(context)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          children: [
            Icon(
              EntryVisuals.iconFor(entry.iconReference),
              color: entry.corrupt
                  ? AppColors.onSurfaceSubtle(brightness)
                  : AppColors.positiveAccent,
            ),
            const SizedBox(width: AppSpacing.innerGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.memberLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    entry.corrupt
                        ? l10n.entryCorruptProjection
                        : l10n.entryArchivedRecoverability,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: entry.corrupt || restoring ? null : onRestore,
              icon: restoring
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.unarchive, size: 18),
              label: Text(
                restoring
                    ? l10n.entryArchiveRestoring
                    : l10n.entryArchiveRestore,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveMessage extends StatelessWidget {
  const _ArchiveMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppColors.onSurfaceSubtle(Theme.of(context).brightness),
      ),
    ),
  );
}
