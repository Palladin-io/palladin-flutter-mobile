import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../cubit/entry_list_cubit.dart';
import '../pages/edit_entry_page.dart';

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
  const VaultEntriesTab({super.key});

  @override
  State<VaultEntriesTab> createState() => _VaultEntriesTabState();
}

class _VaultEntriesTabState extends State<VaultEntriesTab> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expanded = <String>{};
  final Set<String> _revealedFields = <String>{}; // composite "$entryId:$field"
  bool _filtersOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EntryEntity> _filter(List<EntryEntity> entries) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return entries;
    return entries
        .where((e) =>
            e.label.toLowerCase().contains(query) ||
            (e.description?.toLowerCase().contains(query) ?? false) ||
            (e.urlDomain?.toLowerCase().contains(query) ?? false))
        .toList(growable: false);
  }

  void _onToggleReveal(EntryEntity entry) {
    final cubit = context.read<EntryListCubit>();
    if (_expanded.contains(entry.id)) {
      setState(() => _expanded.remove(entry.id));
      cubit.hideEntry(entry.id);
      // Drop any field-level reveal flags so the next expand starts
      // with values masked again.
      _revealedFields.removeWhere((k) => k.startsWith('${entry.id}:'));
      return;
    }

    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.entryErrorCrypto),
        ));
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

  Future<void> _onEditEntry(
    EntryEntity entry,
    Map<String, dynamic>? cachedPayload,
  ) async {
    final cubit = context.read<EntryListCubit>();
    final updated = await EditEntryPage.push(
      context,
      entry: entry,
      cachedPayload: cachedPayload,
      wrappedVK: cubit.wrappedVK,
    );
    if (updated != null && mounted) {
      cubit.replaceEntry(updated);
    }
  }

  Future<void> _copyToClipboard(String value, AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l10n.vaultCopyValue),
        duration: const Duration(seconds: 1),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<EntryListCubit, EntryListState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSearchField(
              controller: _searchController,
              hint: l10n.entrySearchHint,
              filterActive: _filtersOpen,
              onToggleFilter: () =>
                  setState(() => _filtersOpen = !_filtersOpen),
              onChanged: (_) => setState(() {}),
            ),
            if (_filtersOpen) ...[
              const SizedBox(height: 8),
              const _FilterChipsRow(),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: switch (state) {
                EntryListInitial() ||
                EntryListLoading() => const _LoadingView(),
                EntryListError(:final kind) => _ErrorView(
                    kind: kind,
                    onRetry: () =>
                        context.read<EntryListCubit>().loadEntries(),
                  ),
                EntryListLoaded(:final entries, :final revealedEntries) =>
                  _LoadedBody(
                    entries: _filter(entries),
                    revealedEntries: revealedEntries,
                    expanded: _expanded,
                    revealedFields: _revealedFields,
                    onToggleReveal: _onToggleReveal,
                    onToggleFieldReveal: _toggleFieldReveal,
                    onCopy: (value) => _copyToClipboard(value, l10n),
                    onEdit: _onEditEntry,
                    l10n: l10n,
                  ),
              },
            ),
          ],
        );
      },
    );
  }
}

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.entries,
    required this.revealedEntries,
    required this.expanded,
    required this.revealedFields,
    required this.onToggleReveal,
    required this.onToggleFieldReveal,
    required this.onCopy,
    required this.onEdit,
    required this.l10n,
  });

  final List<EntryEntity> entries;
  final Map<String, Map<String, dynamic>> revealedEntries;
  final Set<String> expanded;
  final Set<String> revealedFields;
  final ValueChanged<EntryEntity> onToggleReveal;
  final void Function(String entryId, String field) onToggleFieldReveal;
  final ValueChanged<String> onCopy;
  final void Function(EntryEntity, Map<String, dynamic>?) onEdit;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 96),
      child: entries.isEmpty
          ? _EmptyEntries(l10n: l10n)
          : Container(
              decoration: BoxDecoration(
                color: AppColors.mobileSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.hairline,
                      ),
                    _EntryRow(
                      entry: entries[i],
                      isExpanded: expanded.contains(entries[i].id),
                      payload: revealedEntries[entries[i].id],
                      revealedFields: revealedFields,
                      onToggleReveal: () => onToggleReveal(entries[i]),
                      onToggleFieldReveal: onToggleFieldReveal,
                      onCopy: onCopy,
                      onEdit: () => onEdit(
                        entries[i],
                        revealedEntries[entries[i].id],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _FilterChip(
          label: l10n.entryTypeKey,
          dotColor: AppColors.positiveAccent,
          borderColor: AppColors.positiveAccent.withValues(alpha: 0.35),
        ),
        _FilterChip(
          label: l10n.entryTypeCredential,
          dotColor: AppColors.vaultBlue,
          borderColor: AppColors.vaultSlate.withValues(alpha: 0.15),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.dotColor,
    required this.borderColor,
  });

  final String label;
  final Color dotColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.mobileSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyEntries extends StatelessWidget {
  const _EmptyEntries({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined,
              size: 36, color: AppColors.textTertiaryMobile),
          const SizedBox(height: 12),
          Text(
            l10n.entryEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
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

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: List.generate(
          5,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: _SkeletonRow(brightness: brightness, delay: i * 80),
          ),
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
    _anim = Tween<double>(begin: 0.4, end: 0.85).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.kind, required this.onRetry});

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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
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

// ── Entry row + reveal panel ───────────────────────────────────────

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.isExpanded,
    required this.payload,
    required this.revealedFields,
    required this.onToggleReveal,
    required this.onToggleFieldReveal,
    required this.onCopy,
    required this.onEdit,
  });

  final EntryEntity entry;
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
    final iconColor = entry.type == EntryType.key
        ? AppColors.positiveAccent
        : AppColors.vaultBlue;
    final iconBg = iconColor.withValues(alpha: 0.15);
    final icon = entry.type == EntryType.key ? Icons.vpn_key : Icons.lock;
    final meta = entry.urlDomain ?? entry.description ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top row — name + meta + reveal/arrow buttons.
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconBg,
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textTertiaryMobile,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _SmallIconButton(
                icon: isExpanded ? Icons.visibility_off : Icons.visibility,
                tooltip: l10n.vaultRevealEntry,
                onPressed: onToggleReveal,
              ),
              const SizedBox(width: 6),
              _SmallIconButton(
                icon: Icons.arrow_forward,
                tooltip: l10n.vaultViewEntry,
                onPressed: onEdit,
              ),
            ],
          ),
        ),
        // Reveal panel — animates max-height + opacity.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: isExpanded ? 1.0 : 0.0,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: payload == null
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
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
          _RevealRow(
            icon: Icons.link,
            value: url,
            isMasked: false,
            revealed: true,
            onToggleReveal: null,
            extraTrailing: _SmallIconButton(
              icon: Icons.open_in_new,
              size: 12,
              tooltip: l10n.vaultOpenLink,
              onPressed: () {},
            ),
            onCopy: () => onCopy(url),
          ),
        if (entry.type == EntryType.key) ...[
          if ((payload['value'] as String?)?.isNotEmpty ?? false)
            _RevealRow(
              icon: Icons.vpn_key,
              value: payload['value'] as String,
              isMasked: true,
              revealed: revealedFields.contains('${entry.id}:value'),
              onToggleReveal: () => onToggleFieldReveal(entry.id, 'value'),
              onCopy: () => onCopy(payload['value'] as String),
            ),
        ] else ...[
          if ((payload['username'] as String?)?.isNotEmpty ?? false)
            _RevealRow(
              icon: Icons.person,
              value: payload['username'] as String,
              isMasked: false,
              revealed: true,
              onToggleReveal: null,
              onCopy: () => onCopy(payload['username'] as String),
            ),
          if ((payload['password'] as String?)?.isNotEmpty ?? false)
            _RevealRow(
              icon: Icons.lock,
              value: payload['password'] as String,
              isMasked: true,
              revealed: revealedFields.contains('${entry.id}:password'),
              onToggleReveal: () => onToggleFieldReveal(entry.id, 'password'),
              onCopy: () => onCopy(payload['password'] as String),
            ),
        ],
        if ((payload['notes'] as String?)?.isNotEmpty ?? false)
          _RevealRow(
            icon: Icons.sticky_note_2_outlined,
            value: payload['notes'] as String,
            isMasked: false,
            revealed: true,
            onToggleReveal: null,
            onCopy: () => onCopy(payload['notes'] as String),
          ),
      ],
    );
  }
}

class _RevealRow extends StatelessWidget {
  const _RevealRow({
    required this.icon,
    required this.value,
    required this.isMasked,
    required this.revealed,
    required this.onToggleReveal,
    required this.onCopy,
    this.extraTrailing,
  });

  final IconData icon;
  final String value;
  final bool isMasked;
  final bool revealed;
  final VoidCallback? onToggleReveal;
  final VoidCallback onCopy;
  final Widget? extraTrailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayed = isMasked && !revealed ? '••••••••••••' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: AppColors.textTertiaryMobile),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 10,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (onToggleReveal != null)
            _SmallIconButton(
              icon: revealed ? Icons.visibility_off : Icons.visibility,
              size: 12,
              tooltip: l10n.vaultRevealValue,
              onPressed: onToggleReveal!,
            ),
          if (onToggleReveal != null) const SizedBox(width: 4),
          _SmallIconButton(
            icon: Icons.content_copy,
            size: 12,
            tooltip: l10n.vaultCopyValue,
            onPressed: onCopy,
          ),
          if (extraTrailing != null) ...[
            const SizedBox(width: 4),
            extraTrailing!,
          ],
        ],
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 14,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: size,
            color: AppColors.textTertiaryMobile,
          ),
        ),
      ),
    );
  }
}
