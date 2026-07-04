import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../cubit/import_wizard_state.dart';
import 'import_wizard_widgets.dart';

/// Step 2 — the import preview. Shows the detected format, per-entry rows
/// (passwords always masked), a conflict-resolution strategy selector when
/// collisions exist, and the commit button.
class ImportPreviewList extends StatelessWidget {
  const ImportPreviewList({
    super.key,
    required this.state,
    required this.onToggle,
    required this.onStrategy,
    required this.onImport,
  });

  final ImportWizardPreview state;
  final ValueChanged<int> onToggle;
  final ValueChanged<ImportConflictStrategy> onStrategy;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final included = state.includedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  0,
                  AppSpacing.screenH,
                  AppSpacing.section,
                ),
                sliver: SliverToBoxAdapter(
                  child: _PreviewHeader(state: state, onStrategy: onStrategy),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  0,
                  AppSpacing.screenH,
                  AppSpacing.section,
                ),
                sliver: SliverList.builder(
                  itemCount: state.items.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                    child: _PreviewRow(
                      item: state.items[i],
                      strategy: state.conflictStrategy,
                      onToggle: () => onToggle(i),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.fieldGap,
            AppSpacing.screenH,
            AppSpacing.screenBottom,
          ),
          child: PrimaryButton(
            label: l10n.importAction(included),
            onPressed: included > 0 ? onImport : null,
          ),
        ),
      ],
    );
  }
}

/// Leading (non-scrolling-cost) block above the lazily-built rows: the
/// format summary and, when collisions exist, the conflict-strategy selector.
class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.state, required this.onStrategy});

  final ImportWizardPreview state;
  final ValueChanged<ImportConflictStrategy> onStrategy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryHeader(state: state),
        if (state.conflictCount > 0) ...[
          const SizedBox(height: AppSpacing.section),
          _ConflictSelector(
            strategy: state.conflictStrategy,
            onStrategy: onStrategy,
          ),
        ],
      ],
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.state});

  final ImportWizardPreview state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Badge(
              label: ImportWizardCopy.formatName(l10n, state.format),
              color: AppColors.vaultBlue,
            ),
            const SizedBox(width: AppSpacing.chipGap),
            Text(
              l10n.importEntriesCount(state.items.length),
              style: TextStyle(
                color: AppColors.onSurfaceMuted(brightness),
                fontSize: 12,
              ),
            ),
          ],
        ),
        if (state.skippedCount > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.importSkippedNote(state.skippedCount),
            style: const TextStyle(
              color: AppColors.textTertiaryMobile,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _ConflictSelector extends StatelessWidget {
  const _ConflictSelector({required this.strategy, required this.onStrategy});

  final ImportConflictStrategy strategy;
  final ValueChanged<ImportConflictStrategy> onStrategy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.importConflictStrategyLabel,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.innerGap),
        Row(
          children: [
            for (final s in ImportConflictStrategy.values) ...[
              Expanded(
                child: _StrategyChip(
                  label: ImportWizardCopy.conflictStrategyLabel(l10n, s),
                  selected: s == strategy,
                  onTap: () => onStrategy(s),
                ),
              ),
              if (s != ImportConflictStrategy.values.last)
                const SizedBox(width: AppSpacing.chipGap),
            ],
          ],
        ),
      ],
    );
  }
}

class _StrategyChip extends StatelessWidget {
  const _StrategyChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: AppSpacing.controlHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? AppColors.brandRed.withValues(alpha: 0.12)
              : AppColors.cardFill(brightness),
          border: Border.all(
            color: selected
                ? AppColors.brandRed
                : AppColors.cardBorder(brightness),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? AppColors.brandRed
                : AppColors.onSurfaceMuted(brightness),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.item,
    required this.strategy,
    required this.onToggle,
  });

  final ImportPreviewItem item;
  final ImportConflictStrategy strategy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final active = item.effectiveIncluded(strategy);
    final parsed = item.parsed;
    final subtitle = [
      if (parsed.username != null && parsed.username!.isNotEmpty)
        parsed.username!,
      if (parsed.urlDomain != null) parsed.urlDomain!,
    ].join(' · ');

    return Opacity(
      opacity: active ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.cardFill(brightness),
          border: Border.all(color: AppColors.cardBorder(brightness)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          parsed.name ?? l10n.importUntitledFallback,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.onSurface(brightness),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (item.hasConflict) ...[
                        const SizedBox(width: AppSpacing.chipGap),
                        _Badge(
                          label: l10n.importConflictBadge,
                          color: AppColors.vaultPeach,
                        ),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onSurfaceMuted(brightness),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (parsed.totp != null || parsed.notes != null) ...[
                    const SizedBox(height: AppSpacing.innerGap),
                    Row(
                      children: [
                        if (parsed.totp != null)
                          _MetaChip(
                            icon: Icons.shield_outlined,
                            label: l10n.importTotpBadge,
                          ),
                        if (parsed.totp != null && parsed.notes != null)
                          const SizedBox(width: AppSpacing.chipGap),
                        if (parsed.notes != null)
                          _MetaChip(
                            icon: Icons.notes_outlined,
                            label: l10n.importNotesBadge,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.innerGap),
            // Passwords are never rendered — only a masked marker.
            Checkbox(
              value: item.included,
              onChanged: (_) => onToggle(),
              activeColor: AppColors.brandRed,
              side: BorderSide(color: AppColors.cardBorder(brightness)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.innerGap,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textTertiaryMobile),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textTertiaryMobile,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
