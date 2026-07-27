import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/services/entry_history_service.dart';
import '../../domain/entities/entry_entity.dart';
import '../cubit/entry_history_cubit.dart';

/// On-demand immutable history browser for one Entry.
class EntryHistoryTab extends StatefulWidget {
  const EntryHistoryTab({
    super.key,
    required this.entry,
    required this.onUpdated,
  });

  final EntryEntity entry;
  final ValueChanged<EntryEntity> onUpdated;

  @override
  State<EntryHistoryTab> createState() => _EntryHistoryTabState();
}

class _EntryHistoryTabState extends State<EntryHistoryTab>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      context.read<EntryHistoryCubit>().clearSensitiveState(keepItems: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocConsumer<EntryHistoryCubit, EntryHistoryState>(
      listenWhen: (previous, current) =>
          previous.updatedEntry != current.updatedEntry &&
          current.updatedEntry != null,
      listener: (context, state) {
        widget.onUpdated(state.updatedEntry!);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.entryHistoryRestored)));
      },
      builder: (context, state) {
        if (state.status == EntryHistoryStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.fieldGap,
            AppSpacing.screenH,
            AppSpacing.listBottom,
          ),
          children: [
            WarningZone(
              title: l10n.entryTabHistory.toUpperCase(),
              message: l10n.entryHistorySensitiveWarning,
            ),
            const SizedBox(height: AppSpacing.fieldGap),
            if (state.status == EntryHistoryStatus.error)
              Text(l10n.entryHistoryLoadError),
            if (state.items.isEmpty &&
                state.status != EntryHistoryStatus.error &&
                state.status != EntryHistoryStatus.initial)
              Text(l10n.entryHistoryEmpty),
            for (final version in state.items)
              _VersionCard(
                version: version,
                selected: state.selectedRevision == version.revision,
                busy:
                    state.status == EntryHistoryStatus.revealing ||
                    state.status == EntryHistoryStatus.restoring,
                onReveal: () => _reveal(context, version),
              ),
            if (state.selected != null) ...[
              const SizedBox(height: AppSpacing.fieldGap),
              _DecryptedVersion(
                payload: state.selected!.payload,
                restoring: state.status == EntryHistoryStatus.restoring,
                onRestore: () => _restore(context),
              ),
            ],
            if (state.nextCursor != null)
              TextButton(
                onPressed: () =>
                    context.read<EntryHistoryCubit>().loadMore(widget.entry),
                child: Text(l10n.entryHistoryLoadMore),
              ),
          ],
        );
      },
    );
  }

  void _reveal(BuildContext context, EntryHistoryVersion version) {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.entryHistoryLocked)));
      return;
    }
    context.read<EntryHistoryCubit>().reveal(
      entry: widget.entry,
      version: version,
      privateKey: Uint8List.fromList(auth.privateKey!),
    );
  }

  void _restore(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) return;
    context.read<EntryHistoryCubit>().restore(
      entry: widget.entry,
      privateKey: Uint8List.fromList(auth.privateKey!),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.version,
    required this.selected,
    required this.busy,
    required this.onReveal,
  });

  final EntryHistoryVersion version;
  final bool selected;
  final bool busy;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final actor = '${version.changedByType} ${_shortId(version.changedById)}';
    return Card(
      color: AppColors.cardSurface(brightness),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        title: Text(l10n.entryHistoryVersion(version.revision)),
        subtitle: Text(
          l10n.entryHistoryActor(
            actor,
            DateFormat.yMMMd().add_Hm().format(version.changedAt),
          ),
        ),
        trailing: selected
            ? Icon(Icons.lock_open, color: AppColors.brandRed)
            : const Icon(Icons.lock_outline),
        onTap: busy ? null : onReveal,
      ),
    );
  }
}

class _DecryptedVersion extends StatelessWidget {
  const _DecryptedVersion({
    required this.payload,
    required this.restoring,
    required this.onRestore,
  });

  final Map<String, dynamic> payload;
  final bool restoring;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final field in payload.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.key,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    SelectableText(field.value?.toString() ?? ''),
                  ],
                ),
              ),
            FilledButton.icon(
              onPressed: restoring ? null : onRestore,
              icon: restoring
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore),
              label: Text(l10n.entryHistoryRestore),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortId(String value) {
  if (value.length <= 15) return value;
  return '${value.substring(0, 8)}…${value.substring(value.length - 6)}';
}
