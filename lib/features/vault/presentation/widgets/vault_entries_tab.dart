import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Type of mock entry — drives icon and reveal-panel layout.
enum EntryKind { key, credential }

/// Mock vault entry shown on the Entries tab until the real entries
/// API ships. Kept in this file so the placeholder data stays close
/// to the widget that renders it.
class MockEntry {
  const MockEntry({
    required this.kind,
    required this.name,
    required this.meta,
    required this.icon,
    required this.url,
    this.value,
    this.username,
    this.password,
  });

  final EntryKind kind;
  final String name;
  final String meta;
  final IconData icon;
  final String url;
  final String? value;
  final String? username;
  final String? password;
}

/// Entries tab on the vault detail page.
///
/// Renders a search bar, a single surface card containing all entries
/// separated by hairlines, and a per-entry reveal panel that animates
/// open when the eye icon is tapped — same pattern as the Astro
/// `VaultEntriesMobile.astro` prototype.
class VaultEntriesTab extends StatefulWidget {
  const VaultEntriesTab({super.key, required this.entries});

  final List<MockEntry> entries;

  @override
  State<VaultEntriesTab> createState() => _VaultEntriesTabState();
}

class _VaultEntriesTabState extends State<VaultEntriesTab> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _expanded = <int>{};
  final Set<String> _revealed = <String>{}; // composite "$index:$field"
  bool _filtersOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MockEntry> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.entries;
    return widget.entries
        .where((e) => e.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchBar(
          controller: _searchController,
          hint: l10n.vaultSearchEntries,
          filtersOpen: _filtersOpen,
          onToggleFilters: () => setState(() => _filtersOpen = !_filtersOpen),
          onChanged: (_) => setState(() {}),
        ),
        if (_filtersOpen) ...[
          const SizedBox(height: 8),
          const _FilterChipsRow(),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 96),
            child: _filtered.isEmpty
                ? _EmptyEntries(l10n: l10n)
                : Container(
                    decoration: BoxDecoration(
                      color: AppColors.mobileSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        for (var i = 0; i < _filtered.length; i++) ...[
                          if (i > 0)
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: AppColors.hairline,
                            ),
                          _EntryRow(
                            entry: _filtered[i],
                            isExpanded: _expanded.contains(i),
                            onToggleReveal: () => setState(() {
                              _expanded.contains(i)
                                  ? _expanded.remove(i)
                                  : _expanded.add(i);
                            }),
                            isValueRevealed: _revealed.contains('$i:value'),
                            onToggleValueReveal: () => setState(() {
                              final key = '$i:value';
                              _revealed.contains(key)
                                  ? _revealed.remove(key)
                                  : _revealed.add(key);
                            }),
                            isPasswordRevealed:
                                _revealed.contains('$i:password'),
                            onTogglePasswordReveal: () => setState(() {
                              final key = '$i:password';
                              _revealed.contains(key)
                                  ? _revealed.remove(key)
                                  : _revealed.add(key);
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.hint,
    required this.filtersOpen,
    required this.onToggleFilters,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final bool filtersOpen;
  final VoidCallback onToggleFilters;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.mobileSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search,
            size: 18,
            color: AppColors.textTertiaryMobile,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(
                  color: AppColors.textTertiaryMobile,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: onToggleFilters,
            behavior: HitTestBehavior.opaque,
            child: Icon(
              Icons.tune,
              size: 18,
              color: filtersOpen
                  ? AppColors.brandRed
                  : AppColors.textTertiaryMobile,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _FilterChip(
          label: 'Keys',
          dotColor: AppColors.positiveAccent,
          borderColor: AppColors.positiveAccent.withValues(alpha: 0.35),
        ),
        _FilterChip(
          label: 'Credentials',
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
            l10n.vaultEntriesEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textTertiaryMobile,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Entry row + reveal panel ───────────────────────────────────────

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.isExpanded,
    required this.onToggleReveal,
    required this.isValueRevealed,
    required this.onToggleValueReveal,
    required this.isPasswordRevealed,
    required this.onTogglePasswordReveal,
  });

  final MockEntry entry;
  final bool isExpanded;
  final VoidCallback onToggleReveal;
  final bool isValueRevealed;
  final VoidCallback onToggleValueReveal;
  final bool isPasswordRevealed;
  final VoidCallback onTogglePasswordReveal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final iconColor = entry.kind == EntryKind.key
        ? AppColors.positiveAccent
        : AppColors.vaultBlue;
    final iconBg = iconColor.withValues(alpha: 0.15);

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
                child: Icon(entry.icon, size: 14, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textTertiaryMobile,
                        fontSize: 11,
                      ),
                    ),
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
                onPressed: () {
                  // Detail navigation lands in CVT-32 — no-op for now.
                },
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
                    child: Column(
                      children: [
                        _RevealRow(
                          icon: Icons.link,
                          value: entry.url,
                          isMasked: false,
                          revealed: true,
                          onToggleReveal: null,
                          extraTrailing: _SmallIconButton(
                            icon: Icons.open_in_new,
                            size: 12,
                            tooltip: l10n.vaultOpenLink,
                            onPressed: () {},
                          ),
                          onCopy: () {},
                        ),
                        if (entry.kind == EntryKind.key && entry.value != null)
                          _RevealRow(
                            icon: Icons.vpn_key,
                            value: entry.value!,
                            isMasked: true,
                            revealed: isValueRevealed,
                            onToggleReveal: onToggleValueReveal,
                            onCopy: () {},
                          ),
                        if (entry.kind == EntryKind.credential) ...[
                          if (entry.username != null)
                            _RevealRow(
                              icon: Icons.person,
                              value: entry.username!,
                              isMasked: false,
                              revealed: true,
                              onToggleReveal: null,
                              onCopy: () {},
                            ),
                          if (entry.password != null)
                            _RevealRow(
                              icon: Icons.lock,
                              value: entry.password!,
                              isMasked: true,
                              revealed: isPasswordRevealed,
                              onToggleReveal: onTogglePasswordReveal,
                              onCopy: () {},
                            ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
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
