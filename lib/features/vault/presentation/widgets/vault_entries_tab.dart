import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/permissions.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/secure_clipboard.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/member_index_entry.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../cubit/entry_list_cubit.dart';
import '../pages/entry_detail_page.dart';
import '../pages/entry_archive_page.dart';
import '../pages/entry_share_creation_page.dart';
import 'entry_list_card.dart';

/// Entries tab on the vault detail page.
///
/// Renders a search bar, a single surface card containing all entries
/// separated by hairlines, and a per-entry reveal panel that animates
/// open when the eye icon is tapped — same pattern as the Astro
/// `VaultEntriesMobile.astro` prototype.
///
/// Data is sourced from [EntryListCubit] — see the parent
/// [BlocProvider] in `VaultDetailPage`. Reveal payloads are decrypted
/// on-device and stashed on the cubit's state until the user collapses
/// the panel.
class VaultEntriesTab extends StatefulWidget {
  const VaultEntriesTab({super.key, required this.onImport, this.openArchive});

  final VoidCallback onImport;

  /// Test seam for the pushed Archive route. Production uses
  /// [EntryArchivePage.push].
  final Future<void> Function(BuildContext context)? openArchive;

  @override
  State<VaultEntriesTab> createState() => _VaultEntriesTabState();
}

class _VaultEntriesTabState extends State<VaultEntriesTab> {
  static const _initialRenderLimit = 100;
  static const _renderIncrement = 100;

  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expanded = <String>{};
  final Set<String> _revealedFields = <String>{}; // composite "$entryId:$field"
  Timer? _searchDebounce;
  String _searchQuery = '';
  int _renderLimit = _initialRenderLimit;
  int _filteredCount = 0;
  List<EntryEntity>? _filterSource;
  String? _filterQuery;
  List<EntryEntity> _filteredEntries = const [];

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<EntryEntity> _filter(List<EntryEntity> entries) {
    if (identical(entries, _filterSource) && _searchQuery == _filterQuery) {
      return _filteredEntries;
    }
    final query = _searchQuery;
    final filtered =
        entries
            .where((e) => e.lifecycleState == MemberEntryState.active)
            .where(
              (e) =>
                  query.isEmpty ||
                  e.label.toLowerCase().contains(query) ||
                  (e.description?.toLowerCase().contains(query) ?? false) ||
                  (e.urlDomain?.toLowerCase().contains(query) ?? false),
            )
            .toList(growable: false)
          ..sort((left, right) => left.label.compareTo(right.label));
    _filterSource = entries;
    _filterQuery = query;
    _filteredEntries = filtered;
    return filtered;
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = value.trim().toLowerCase();
        _renderLimit = _initialRenderLimit;
      });
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.metrics.extentAfter < 400 &&
        _renderLimit < _filteredCount) {
      setState(() => _renderLimit += _renderIncrement);
    }
    return false;
  }

  void _retrySync() {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) return;
    final keyCopy = Uint8List.fromList(auth.privateKey!);
    context
        .read<EntryListCubit>()
        .loadIndexedEntries(keyCopy)
        .whenComplete(() => keyCopy.fillRange(0, keyCopy.length, 0));
  }

  Future<void> _openArchive() async {
    final open = widget.openArchive;
    if (open != null) {
      await open(context);
    } else {
      await EntryArchivePage.push(
        context,
        context.read<EntryListCubit>().vaultId,
      );
    }
    if (mounted) _retrySync();
  }

  void _onToggleReveal(EntryEntity entry) {
    final cubit = context.read<EntryListCubit>();
    if (_expanded.contains(entry.id)) {
      // Collapse the panel AND drop any field-level reveal flags atomically
      // so the next expand starts with values masked again. Keeping both
      // mutations inside a single setState avoids relying on an unrelated
      // mutation to schedule the rebuild.
      setState(() {
        _expanded.remove(entry.id);
        _revealedFields.removeWhere((k) => k.startsWith('${entry.id}:'));
      });
      cubit.hideEntry(entry.id);
      return;
    }

    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.entryErrorCrypto),
          ),
        );
      return;
    }

    setState(() => _expanded.add(entry.id));
    // Defensive copy of the unlocked private key so the cubit can mutate
    // it without touching the auth bloc's state. Zero out in finally —
    // `EntryCryptoService.unwrapVK` already disposes its own SecureKey
    // wrapper, but the raw `Uint8List` we hand it would otherwise linger
    // on the heap with the secret key material.
    final keyCopy = Uint8List.fromList(auth.privateKey!);
    cubit
        .revealEntry(entryId: entry.id, privateKey: keyCopy)
        .whenComplete(() => keyCopy.fillRange(0, keyCopy.length, 0));
  }

  void _toggleFieldReveal(String entryId, String field) {
    setState(() {
      final key = '$entryId:$field';
      if (_revealedFields.contains(key)) {
        _revealedFields.remove(key);
      } else {
        _revealedFields.add(key);
      }
    });
  }

  Future<void> _onEditEntry(EntryEntity entry) async {
    final cubit = context.read<EntryListCubit>();
    final result = await EntryDetailPage.push(
      context,
      entry: entry,
      wrappedVK: cubit.wrappedVK,
    );
    if (!mounted) return;
    if (result is EntryDetailUpdated) {
      cubit.replaceEntry(result.entry);
    } else if (result is EntryDetailDeleted) {
      cubit.removeEntry(result.entryId);
    }
  }

  Future<void> _copyToClipboard(String value, AppLocalizations l10n) async {
    await SecureClipboard.copy(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.vaultCopyValue),
          duration: const Duration(seconds: 1),
        ),
      );
  }

  List<Widget> _loadedSlivers({
    required List<EntryEntity> entries,
    required bool hasActiveEntries,
    required Map<String, Map<String, dynamic>> revealedEntries,
    required AppLocalizations l10n,
  }) {
    if (entries.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: hasActiveEntries
              ? _NoMatchingEntries(l10n: l10n)
              : _EmptyEntries(l10n: l10n, onImport: widget.onImport),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.only(bottom: AppSpacing.listBottom),
        sliver: SliverList.separated(
          itemCount: entries.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: AppSpacing.cardGap),
          itemBuilder: (context, i) => EntryListCard(
            key: ValueKey(entries[i].id),
            entry: entries[i],
            isExpanded: _expanded.contains(entries[i].id),
            payload: revealedEntries[entries[i].id],
            revealedFields: _revealedFields,
            onToggleReveal: () => _onToggleReveal(entries[i]),
            onToggleFieldReveal: _toggleFieldReveal,
            onCopy: (value) => _copyToClipboard(value, l10n),
            onEdit: () => _onEditEntry(entries[i]),
            onShare: _canShare
                ? () => EntryShareCreationPage.push(context, entries[i])
                : null,
          ),
        ),
      ),
    ];
  }

  String _errorMessage(EntryErrorKind kind, AppLocalizations l10n) {
    return switch (kind) {
      EntryErrorKind.notFound => l10n.entryErrorNotFound,
      EntryErrorKind.forbidden => l10n.entryErrorForbidden,
      EntryErrorKind.validation => l10n.entryErrorValidation,
      EntryErrorKind.cryptoFailure => l10n.entryErrorCrypto,
      EntryErrorKind.networkError => l10n.errorCannotConnectToServer,
      EntryErrorKind.unknown => l10n.entryErrorUnknown,
    };
  }

  bool get _canShare {
    final auth = context.read<AuthBloc?>()?.state;
    return auth is AuthAuthenticated &&
        !auth.isVaultLocked &&
        auth.privateKey != null &&
        auth.emailVerified &&
        (auth.permissions & Permissions.vaultManage) != 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocConsumer<EntryListCubit, EntryListState>(
      listenWhen: (prev, next) {
        // Fire only when the loaded state's transient error tick changes —
        // each per-row failure (reveal/delete) bumps the tick.
        if (next is! EntryListLoaded) return false;
        if (prev is! EntryListLoaded) return next.transientErrorKind != null;
        return next.transientErrorTick != prev.transientErrorTick &&
            next.transientErrorKind != null;
      },
      listener: (context, state) {
        if (state is! EntryListLoaded) return;
        final kind = state.transientErrorKind;
        if (kind == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(_errorMessage(kind, l10n)),
              duration: const Duration(seconds: 3),
            ),
          );
      },
      builder: (context, state) {
        // Search scrolls with the entries list (canonical Vaults pattern): it
        // is the first sliver of a single CustomScrollView, so an overscroll
        // never reveals a background strip between a pinned search bar and a
        // separate scroll area. Each state contributes the slivers below it.
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.fieldGap),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppSearchField(
                          controller: _searchController,
                          hint: l10n.entrySearchHint,
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.innerGap),
                      IconButton(
                        tooltip: l10n.entryArchiveTitle,
                        onPressed: _openArchive,
                        icon: const Icon(Icons.archive_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              ...switch (state) {
                EntryListInitial() ||
                EntryListLoading() => const [_LoadingSliver()],
                EntryListError(:final kind) => [
                  _ErrorSliver(kind: kind, onRetry: _retrySync),
                ],
                EntryListLoaded(:final entries, :final revealedEntries) =>
                  _loadedSlivers(
                    entries: _prepareEntries(entries),
                    hasActiveEntries: entries.any(
                      (entry) =>
                          entry.lifecycleState == MemberEntryState.active,
                    ),
                    revealedEntries: revealedEntries,
                    l10n: l10n,
                  ),
              },
            ],
          ),
        );
      },
    );
  }

  List<EntryEntity> _prepareEntries(List<EntryEntity> entries) {
    final filtered = _filter(entries);
    _filteredCount = filtered.length;
    final visible = filtered.take(_renderLimit).toList(growable: false);
    return visible;
  }
}

class _EmptyEntries extends StatelessWidget {
  const _EmptyEntries({required this.l10n, required this.onImport});
  final AppLocalizations l10n;
  final VoidCallback onImport;
  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: const Offset(0, -(AppSpacing.xxxl + AppSpacing.sm)),
    child: AppEmptyState(
      icon: Icons.inbox_outlined,
      title: l10n.entryEmpty,
      hint: l10n.entryEmptyAdd,
      actionLabel: l10n.vaultActionImport,
      actionIcon: Icons.file_upload_outlined,
      onAction: onImport,
    ),
  );
}

class _NoMatchingEntries extends StatelessWidget {
  const _NoMatchingEntries({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        l10n.searchResultsEmpty,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textTertiaryMobile,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _LoadingSliver extends StatelessWidget {
  const _LoadingSliver();

  @override
  Widget build(BuildContext context) {
    // search → first skeleton row gap (fieldGap) is owned by the search bar.
    return SliverList.list(
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
          child: SkeletonBox(height: 56, delay: Duration(milliseconds: i * 80)),
        ),
      ),
    );
  }
}

class _ErrorSliver extends StatelessWidget {
  const _ErrorSliver({required this.kind, required this.onRetry});

  final EntryErrorKind kind;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final message = switch (kind) {
      EntryErrorKind.notFound => l10n.entryErrorNotFound,
      EntryErrorKind.forbidden => l10n.entryErrorForbidden,
      EntryErrorKind.validation => l10n.entryErrorValidation,
      EntryErrorKind.cryptoFailure => l10n.entryErrorCrypto,
      EntryErrorKind.networkError => l10n.errorCannotConnectToServer,
      EntryErrorKind.unknown => l10n.entryErrorUnknown,
    };
    final brightness = Theme.of(context).brightness;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.fieldGap),
            TextButton(
              onPressed: onRetry,
              child: Text(
                l10n.vaultRetry,
                style: const TextStyle(color: AppColors.brandRed),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
