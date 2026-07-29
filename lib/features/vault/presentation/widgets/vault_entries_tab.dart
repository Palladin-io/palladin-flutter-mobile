import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/secure_clipboard.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../public_asset_catalog/presentation/widgets/public_asset_image.dart';
import '../../../public_asset_catalog/domain/entities/public_asset.dart';
import '../../../public_asset_catalog/domain/services/website_icon_service.dart';
import '../../../../core/di/injection.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/member_index_entry.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../cubit/entry_list_cubit.dart';
import '../pages/entry_detail_page.dart';
import '../pages/entry_archive_page.dart';
import 'entry_field_row.dart';
import 'vault_visuals.dart';
import 'encrypted_asset_image.dart';
import '../../data/services/encrypted_presentation_asset_service.dart';

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
  const VaultEntriesTab({super.key, this.openArchive});

  /// Test seam for the pushed Archive route. Production uses
  /// [EntryArchivePage.push].
  final Future<void> Function(BuildContext context)? openArchive;

  @override
  State<VaultEntriesTab> createState() => _VaultEntriesTabState();
}

class _VaultEntriesTabState extends State<VaultEntriesTab> {
  static const _initialRenderLimit = 100;
  static const _renderIncrement = 100;
  static const _maxWebsitePollAttempts = 10;

  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expanded = <String>{};
  final Set<String> _revealedFields = <String>{}; // composite "$entryId:$field"
  final Map<String, PublicAsset> _websiteAssets = <String, PublicAsset>{};
  Timer? _websiteAssetPoll;
  Timer? _searchDebounce;
  String _websiteAssetKey = '';
  String _searchQuery = '';
  int _renderLimit = _initialRenderLimit;
  int _filteredCount = 0;

  @override
  void dispose() {
    _websiteAssetPoll?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleWebsiteAssets(List<EntryEntity> entries) {
    final hostnames =
        entries
            .map((entry) => entry.icon)
            .whereType<String>()
            .where((reference) => reference.startsWith('website:'))
            .map((reference) => reference.substring('website:'.length))
            .toSet()
            .toList()
          ..sort();
    final key = hostnames.join(',');
    if (key == _websiteAssetKey) return;
    _websiteAssetKey = key;
    _websiteAssetPoll?.cancel();
    if (hostnames.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && key == _websiteAssetKey) {
        _resolveWebsiteAssets(hostnames, key, 0);
      }
    });
  }

  Future<void> _resolveWebsiteAssets(
    List<String> hostnames,
    String key,
    int attempt,
  ) async {
    if (!getIt.isRegistered<WebsiteIconService>()) return;
    final unresolved = hostnames
        .where((hostname) => !_websiteAssets.containsKey(hostname))
        .toList(growable: false);
    if (unresolved.isEmpty) return;
    final resolved = await getIt<WebsiteIconService>().resolveBatch(unresolved);
    if (!mounted || key != _websiteAssetKey) return;
    if (resolved.isNotEmpty) {
      setState(() => _websiteAssets.addAll(resolved));
    }
    if (_websiteAssets.keys.toSet().containsAll(hostnames) ||
        attempt >= _maxWebsitePollAttempts) {
      return;
    }
    _websiteAssetPoll = Timer(
      const Duration(seconds: 2),
      () => _resolveWebsiteAssets(hostnames, key, attempt + 1),
    );
  }

  List<EntryEntity> _filter(List<EntryEntity> entries) {
    final query = _searchQuery;
    return entries
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
    required Map<String, Map<String, dynamic>> revealedEntries,
    required AppLocalizations l10n,
  }) {
    if (entries.isEmpty) {
      return [SliverToBoxAdapter(child: _EmptyEntries(l10n: l10n))];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.only(bottom: AppSpacing.listBottom),
        sliver: SliverList.separated(
          itemCount: entries.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: AppSpacing.cardGap),
          itemBuilder: (context, i) => _EntryCard(
            entry: entries[i],
            websiteAssets: _websiteAssets,
            isExpanded: _expanded.contains(entries[i].id),
            payload: revealedEntries[entries[i].id],
            revealedFields: _revealedFields,
            onToggleReveal: () => _onToggleReveal(entries[i]),
            onToggleFieldReveal: _toggleFieldReveal,
            onCopy: (value) => _copyToClipboard(value, l10n),
            onEdit: () => _onEditEntry(entries[i]),
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
    _scheduleWebsiteAssets(visible);
    return visible;
  }
}

class _EmptyEntries extends StatelessWidget {
  const _EmptyEntries({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxxl,
        horizontal: AppSpacing.screenH,
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 36,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.entryEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.chipGap),
          Text(
            l10n.entryEmptyAdd,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textTertiaryMobile,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingSliver extends StatelessWidget {
  const _LoadingSliver();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // search → first skeleton row gap (fieldGap) is owned by the search bar.
    return SliverList.list(
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
          child: _SkeletonRow(brightness: brightness, delay: i * 80),
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatefulWidget {
  const _SkeletonRow({required this.brightness, required this.delay});
  final Brightness brightness;
  final int delay;

  @override
  State<_SkeletonRow> createState() => _SkeletonRowState();
}

class _SkeletonRowState extends State<_SkeletonRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
    _anim = Tween<double>(
      begin: 0.4,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.onSurface(widget.brightness).withValues(alpha: 0.07);
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Container(
        height: 56,
        decoration: BoxDecoration(
          color: base.withValues(alpha: base.a * _anim.value),
          border: Border(
            bottom: BorderSide(
              color: AppColors.cardBorder(widget.brightness),
              width: 1,
            ),
          ),
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

// ── Entry card + reveal panel ──────────────────────────────────────

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.websiteAssets,
    required this.isExpanded,
    required this.payload,
    required this.revealedFields,
    required this.onToggleReveal,
    required this.onToggleFieldReveal,
    required this.onCopy,
    required this.onEdit,
  });

  final EntryEntity entry;
  final Map<String, PublicAsset> websiteAssets;
  final bool isExpanded;
  final Map<String, dynamic>? payload;
  final Set<String> revealedFields;
  final VoidCallback onToggleReveal;
  final void Function(String entryId, String field) onToggleFieldReveal;
  final ValueChanged<String> onCopy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final interactive =
        entry.lifecycleState == MemberEntryState.active && !entry.corrupt;
    final meta = entry.corrupt
        ? l10n.entryCorruptProjection
        : switch (entry.lifecycleState) {
            MemberEntryState.active =>
              entry.urlDomain ?? entry.description ?? '',
            MemberEntryState.archived => l10n.entryArchivedRecoverability,
            MemberEntryState.deleted => l10n.entryDeletedRecoverability,
          };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: interactive ? onEdit : null,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.cardBorder(brightness),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header row — icon + name/meta + action buttons.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  AppSpacing.md,
                  0,
                  AppSpacing.cardGap,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _EntryIconWidget(
                      entry: entry,
                      websiteAssets: websiteAssets,
                    ),
                    const SizedBox(width: AppSpacing.cardGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.onSurface(brightness),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.onSurfaceSubtle(brightness),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.chipGap),
                    if (interactive) ...[
                      EntrySmallIconButton(
                        icon: isExpanded
                            ? Icons.visibility_off
                            : Icons.visibility,
                        tooltip: l10n.vaultRevealEntry,
                        onPressed: onToggleReveal,
                      ),
                      const SizedBox(width: AppSpacing.chipGap),
                      EntrySmallIconButton(
                        icon: Icons.arrow_forward,
                        tooltip: l10n.vaultViewEntry,
                        onPressed: onEdit,
                      ),
                    ],
                  ],
                ),
              ),
              // Reveal panel — animates open/closed.
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: isExpanded ? 1.0 : 0.0,
                  child: isExpanded
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: payload == null
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: AppSpacing.innerGap,
                                  ),
                                  child: Center(
                                    child: SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: AppColors.brandRed,
                                      ),
                                    ),
                                  ),
                                )
                              : _RevealPanel(
                                  entry: entry,
                                  payload: payload!,
                                  revealedFields: revealedFields,
                                  onToggleFieldReveal: onToggleFieldReveal,
                                  onCopy: onCopy,
                                ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevealPanel extends StatelessWidget {
  const _RevealPanel({
    required this.entry,
    required this.payload,
    required this.revealedFields,
    required this.onToggleFieldReveal,
    required this.onCopy,
  });

  final EntryEntity entry;
  final Map<String, dynamic> payload;
  final Set<String> revealedFields;
  final void Function(String entryId, String field) onToggleFieldReveal;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final url = (payload['url'] as String?) ?? entry.urlDomain;
    return Column(
      children: [
        if (url != null && url.isNotEmpty)
          EntryFieldRow(
            icon: Icons.link,
            value: url,
            isMasked: false,
            revealed: true,
            onToggleReveal: null,
            valueFontSize: 10,
            actionIconSize: 12,
            extraTrailing: EntrySmallIconButton(
              icon: Icons.open_in_new,
              size: 12,
              tooltip: l10n.vaultOpenLink,
              onPressed: () {},
            ),
            onCopy: () => onCopy(url),
          ),
        if (entry.type == EntryType.key) ...[
          if ((payload['value'] as String?)?.isNotEmpty ?? false)
            EntryFieldRow(
              icon: Icons.vpn_key,
              value: payload['value'] as String,
              isMasked: true,
              revealed: revealedFields.contains('${entry.id}:value'),
              onToggleReveal: () => onToggleFieldReveal(entry.id, 'value'),
              valueFontSize: 10,
              actionIconSize: 12,
              onCopy: () => onCopy(payload['value'] as String),
            ),
        ] else if (entry.type == EntryType.script) ...[
          if ((payload['script'] as String?)?.isNotEmpty ?? false)
            EntryFieldRow(
              icon: Icons.terminal,
              value: payload['script'] as String,
              isMasked: true,
              revealed: revealedFields.contains('${entry.id}:script'),
              onToggleReveal: () => onToggleFieldReveal(entry.id, 'script'),
              valueFontSize: 10,
              actionIconSize: 12,
              onCopy: () => onCopy(payload['script'] as String),
            ),
        ] else ...[
          if ((payload['username'] as String?)?.isNotEmpty ?? false)
            EntryFieldRow(
              icon: Icons.person,
              value: payload['username'] as String,
              isMasked: false,
              revealed: true,
              onToggleReveal: null,
              valueFontSize: 10,
              actionIconSize: 12,
              onCopy: () => onCopy(payload['username'] as String),
            ),
          if ((payload['password'] as String?)?.isNotEmpty ?? false)
            EntryFieldRow(
              icon: Icons.lock,
              value: payload['password'] as String,
              isMasked: true,
              revealed: revealedFields.contains('${entry.id}:password'),
              onToggleReveal: () => onToggleFieldReveal(entry.id, 'password'),
              valueFontSize: 10,
              actionIconSize: 12,
              onCopy: () => onCopy(payload['password'] as String),
            ),
        ],
        if ((payload['notes'] as String?)?.isNotEmpty ?? false)
          EntryFieldRow(
            icon: Icons.sticky_note_2_outlined,
            value: payload['notes'] as String,
            isMasked: false,
            revealed: true,
            onToggleReveal: null,
            valueFontSize: 10,
            actionIconSize: 12,
            onCopy: () => onCopy(payload['notes'] as String),
          ),
      ],
    );
  }
}

// ── Entry icon ─────────────────────────────────────────────────────

/// Renders the entry's icon as a 40×40 circle (matching vault/agent list
/// icons). Uses the `entry.icon`
/// field when set — custom URLs (publicly readable S3) become a network
/// image with a cache-busting `?v=` param tied to `entry.updatedAt`,
/// preset names map to the matching [EntryVisuals] palette color.
/// Falls back to a type-based icon when `entry.icon` is null.
class _EntryIconWidget extends StatelessWidget {
  const _EntryIconWidget({required this.entry, required this.websiteAssets});

  final EntryEntity entry;
  final Map<String, PublicAsset> websiteAssets;

  @override
  Widget build(BuildContext context) {
    final icon = entry.icon;

    if (icon?.startsWith('asset:') ?? false) {
      return SizedBox(
        width: 40,
        height: 40,
        child: ClipOval(
          child: EncryptedAssetImage(
            reference: icon!,
            target: PresentationAssetTarget.entry,
            vaultId: entry.vaultId,
            entryId: entry.id,
            width: 40,
            height: 40,
            fallback: _presetIcon(null),
          ),
        ),
      );
    }

    if (icon?.startsWith('public-asset:') ?? false) {
      return SizedBox(
        width: 40,
        height: 40,
        child: ClipOval(
          child: PublicAssetImage(
            reference: icon!,
            width: 40,
            height: 40,
            fallback: _presetIcon(null),
          ),
        ),
      );
    }

    if (icon?.startsWith('website:') ?? false) {
      final asset = websiteAssets[icon!.substring('website:'.length)];
      if (asset != null) {
        return SizedBox(
          width: 40,
          height: 40,
          child: ClipOval(
            child: Image.network(
              asset.deliveryUrl.toString(),
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _presetIcon(null),
            ),
          ),
        );
      }
    }

    if (!EntryVisuals.isCustomUrl(icon)) {
      return _presetIcon(icon);
    }

    return _presetIcon(null);
  }

  Widget _presetIcon(String? name) {
    final choices = EntryVisuals.iconChoices;
    final fallbackName = switch (entry.type) {
      EntryType.key => choices.first.name,
      EntryType.credential => 'lock',
      EntryType.script => 'terminal',
    };
    final choice = choices.firstWhere(
      (c) => c.name == (name ?? EntryVisuals.defaultIconName),
      orElse: () => choices.firstWhere(
        (c) => c.name == fallbackName,
        orElse: () => choices.first,
      ),
    );
    final iconColor = choice.paletteColor;
    final iconBg = iconColor.withValues(alpha: 0.15);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
      child: Icon(choice.icon, size: 20, color: iconColor),
    );
  }
}
