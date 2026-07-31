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
import '../../data/services/canonical_entry_detail_service.dart';
import '../cubit/recently_deleted_cubit.dart';

class RecentlyDeletedPage extends StatefulWidget {
  const RecentlyDeletedPage({super.key, required this.vaultId});

  final String vaultId;

  static Future<void> push(BuildContext context, String vaultId) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => BlocProvider(
            create: (_) => getIt<RecentlyDeletedCubit>(param1: vaultId)..load(),
            child: RecentlyDeletedPage(vaultId: vaultId),
          ),
        ),
      );

  @override
  State<RecentlyDeletedPage> createState() => _RecentlyDeletedPageState();
}

class _RecentlyDeletedPageState extends State<RecentlyDeletedPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _restore(String entryId) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      context.read<RecentlyDeletedCubit>().lock();
      return;
    }
    final key = Uint8List.fromList(auth.privateKey!);
    try {
      await context.read<RecentlyDeletedCubit>().restore(entryId, key);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<void> _confirmPurge(String entryId) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.entryDeletedPurgeTitle),
        content: Text(l10n.entryDeletedPurgeWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.vaultCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.entryDeletedPurgeConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<RecentlyDeletedCubit>().purge(entryId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (_, state) =>
          state is! AuthAuthenticated || state.isVaultLocked,
      listener: (_, _) => context.read<RecentlyDeletedCubit>().lock(),
      child: AppScreen.appBar(
        appBar: AppBar(
          titleSpacing: 0,
          centerTitle: false,
          title: AppBarTitle(
            title: l10n.entryDeletedTitle,
            subtitle: l10n.entryDeletedSubtitle,
          ),
        ),
        body: Padding(
          padding: AppScreen.screenPadding,
          child: BlocConsumer<RecentlyDeletedCubit, RecentlyDeletedState>(
            listenWhen: (previous, next) =>
                next is RecentlyDeletedLoaded &&
                next.transientError != null &&
                (previous is! RecentlyDeletedLoaded ||
                    previous.errorTick != next.errorTick),
            listener: (context, state) {
              final loaded = state as RecentlyDeletedLoaded;
              final message =
                  loaded.transientError == CanonicalEntryDetailError.conflict
                  ? l10n.entryArchiveConflict
                  : l10n.entryErrorUnknown;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(message)));
            },
            builder: (context, state) => CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.fieldGap),
                    child: AppSearchField(
                      controller: _search,
                      hint: l10n.entryDeletedSearchHint,
                      onChanged: context.read<RecentlyDeletedCubit>().search,
                    ),
                  ),
                ),
                ...switch (state) {
                  RecentlyDeletedLoading() => const [
                    SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brandRed,
                        ),
                      ),
                    ),
                  ],
                  RecentlyDeletedLocked() => [
                    SliverFillRemaining(
                      child: _Message(text: l10n.entryHistoryLocked),
                    ),
                  ],
                  RecentlyDeletedError() => [
                    SliverFillRemaining(
                      child: _Message(text: l10n.entryErrorUnknown),
                    ),
                  ],
                  RecentlyDeletedLoaded(
                    :final visibleItems,
                    :final pendingIds,
                  ) =>
                    visibleItems.isEmpty
                        ? [
                            SliverFillRemaining(
                              child: _Message(text: l10n.entryDeletedEmpty),
                            ),
                          ]
                        : [
                            SliverList.separated(
                              itemCount: visibleItems.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.cardGap),
                              itemBuilder: (_, index) {
                                final item = visibleItems[index];
                                return _DeletedRow(
                                  item: item,
                                  pending: pendingIds.contains(item.entryId),
                                  onRestore: () => _restore(item.entryId),
                                  onPurge: () => _confirmPurge(item.entryId),
                                );
                              },
                            ),
                          ],
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeletedRow extends StatelessWidget {
  const _DeletedRow({
    required this.item,
    required this.pending,
    required this.onRestore,
    required this.onPurge,
  });

  final RecentlyDeletedItem item;
  final bool pending;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final local = item.presentation;
    final safe = local != null && !local.corrupt;
    final label = safe ? local.memberLabel : _shortId(item.entryId);
    final deadline = MaterialLocalizations.of(
      context,
    ).formatMediumDate(item.purgeAt.toLocal());
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        border: Border.all(color: AppColors.cardBorder(brightness)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.entryDeletedPurgeAt(deadline),
              style: TextStyle(color: AppColors.onSurfaceSubtle(brightness)),
            ),
            const SizedBox(height: AppSpacing.innerGap),
            Row(
              children: [
                TextButton.icon(
                  onPressed: safe && !pending ? onRestore : null,
                  icon: const Icon(Icons.restore),
                  label: Text(l10n.entryDeletedRestore),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: pending ? null : onPurge,
                  icon: const Icon(Icons.delete_forever),
                  label: Text(l10n.entryDeletedPurgeConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shortId(String value) {
    if (value.length <= 15) return value;
    return '${value.substring(0, 8)}…${value.substring(value.length - 6)}';
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(text, textAlign: TextAlign.center));
}
