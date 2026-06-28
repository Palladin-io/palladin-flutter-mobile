import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A single selectable option — a stable [value] plus its display [label].
typedef MultiSelectOption = ({String value, String label});

/// A compact, mobile-friendly multi-select **autocomplete** control.
///
/// Renders a labelled trigger field showing the current selection summary
/// (placeholder when empty, the single option's label when one is selected,
/// or "{n} selected" for many). Tapping it expands an **inline** panel — a
/// typeahead search field over a live-filtered checklist — within the
/// surrounding scroll view (no nested bottom-sheet, which avoids stacked-modal
/// pitfalls). Fully controlled: it never mutates [selected]; every toggle
/// emits the next [Set] via [onChanged].
class MultiSelectDropdown extends StatefulWidget {
  const MultiSelectDropdown({
    super.key,
    required this.label,
    required this.placeholder,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  /// Facet name shown on the left of the trigger (e.g. "Agent").
  final String label;

  /// Summary shown when nothing is selected (e.g. "All agents").
  final String placeholder;

  final List<MultiSelectOption> options;

  /// Currently selected option values. Empty = "all".
  final Set<String> selected;

  /// Emits the next selection when an option is toggled.
  final ValueChanged<Set<String>> onChanged;

  @override
  State<MultiSelectDropdown> createState() => _MultiSelectDropdownState();
}

class _MultiSelectDropdownState extends State<MultiSelectDropdown> {
  bool _open = false;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleOpen() {
    setState(() {
      _open = !_open;
      // Reset the typeahead query when collapsing so reopening starts clean.
      if (!_open) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  String _summary(AppLocalizations l10n) {
    final selected = widget.selected;
    if (selected.isEmpty) return widget.placeholder;
    if (selected.length == 1) {
      for (final o in widget.options) {
        if (o.value == selected.first) return o.label;
      }
    }
    return l10n.multiSelectNSelected(selected.length);
  }

  void _toggle(String value) {
    final next = Set<String>.of(widget.selected);
    if (!next.remove(value)) next.add(value);
    widget.onChanged(next);
  }

  List<MultiSelectOption> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options
        .where((o) => o.label.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final hasSelection = widget.selected.isNotEmpty;
    final filtered = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleOpen,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.cardPadding,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.cardSurface(brightness),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.inputBorder(brightness)),
            ),
            child: Row(
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _summary(l10n),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: hasSelection
                          ? AppColors.onSurface(brightness)
                          : AppColors.onSurfaceSubtle(brightness),
                      fontSize: 12,
                      fontWeight: hasSelection
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppColors.onSurfaceSubtle(brightness),
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardSurface(brightness),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.inputBorder(brightness)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Typeahead search field — filters the checklist live.
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.cardPadding,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 16,
                        color: AppColors.onSurfaceSubtle(brightness),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (q) => setState(() => _query = q),
                          cursorColor: AppColors.brandRed,
                          style: TextStyle(
                            color: AppColors.onSurface(brightness),
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: l10n.multiSelectSearchHint,
                            hintStyle: TextStyle(
                              color: AppColors.onSurfaceSubtle(brightness),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.inputBorder(brightness)),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.cardPadding,
                      vertical: AppSpacing.md,
                    ),
                    child: Text(
                      l10n.multiSelectNoResults,
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  for (final option in filtered)
                    _OptionTile(
                      label: option.label,
                      selected: widget.selected.contains(option.value),
                      onTap: () => _toggle(option.value),
                      brightness: brightness,
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: selected
                  ? AppColors.brandRed
                  : AppColors.onSurfaceSubtle(brightness),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
