import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/sheet_surface.dart';
import '../../../grants/presentation/widgets/grant_format.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../audit_log_format.dart';

/// A single expandable audit log row.
///
/// Collapsed: a subtle timestamp, the event sentence/label and outlined
/// context chips, separated from the next event by a single line. Tapping expands to reveal the
/// entry label, the agent's reason and any non-sensitive metadata (grant id,
/// method, ip, device…). All values are metadata only — never secrets.
class AuditLogRow extends StatefulWidget {
  const AuditLogRow({
    super.key,
    required this.entry,
    required this.agentNames,
    this.showDivider = true,
  });

  final AuditLogEntry entry;
  final bool showDivider;
  final Map<String, String> agentNames;

  @override
  State<AuditLogRow> createState() => _AuditLogRowState();
}

class _AuditLogRowState extends State<AuditLogRow> {
  bool _chipsExpanded = false;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  void _fontsChanged() => setState(() {});

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final entry = widget.entry;
    final color = auditEventColor(entry.eventType);
    // Generic events compose a full "who did what to which object" sentence
    // (bold names); grant.* / credential.* / unknown keep the legacy
    // label + actor line.
    final sentence = auditEventSentence(l10n, entry, widget.agentNames);
    final actor = auditActorName(l10n, entry, widget.agentNames);
    final agentLabel = entry.agentName ?? widget.agentNames[entry.agentId];
    final method = entry.metadata['method'];
    final contextLabels = [
      if (entry.entryLabel?.isNotEmpty == true) entry.entryLabel!,
      if (entry.resolvedVaultName?.isNotEmpty == true) entry.resolvedVaultName!,
      if (agentLabel?.isNotEmpty == true) agentLabel!,
      if (method?.isNotEmpty == true) auditMetadataValue('method', method!),
    ];

    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: () => _showDetails(context, sentence, actor, contextLabels),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: widget.showDivider
                  ? BorderSide(color: AppColors.cardBorder(brightness))
                  : BorderSide.none,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sentence != null)
                Text.rich(
                  _sentenceText(sentence, brightness, actor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              else ...[
                Text(
                  auditEventLabel(l10n, entry.eventType, entry.rawEventType),
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  actor,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: AppSpacing.innerGap),
              _metadata(context, contextLabels, color),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(
    BuildContext context,
    List<AuditSentenceSpan>? sentence,
    String actor,
    List<String> labels,
  ) {
    final entry = widget.entry;
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final title = auditEventLabel(l10n, entry.eventType, entry.rawEventType);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: SheetSurface(
          title: title,
          showClose: true,
          onClose: () => Navigator.pop(sheetContext),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sentence != null)
                  Text.rich(_sentenceText(sentence, brightness, actor))
                else
                  Text('$title · $actor'),
                const SizedBox(height: AppSpacing.innerGap),
                Text(
                  auditTimestamp(
                    entry.occurredAt,
                    Localizations.localeOf(context).toString(),
                  ),
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                Wrap(
                  spacing: AppSpacing.chipGap,
                  runSpacing: AppSpacing.chipGap,
                  children: [
                    for (final label in labels)
                      StatusBadge(
                        label: label,
                        color: AppColors.onSurfaceMuted(brightness),
                      ),
                  ],
                ),
                _ExpandedDetail(entry: entry),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metadata(
    BuildContext context,
    List<String> contextLabels,
    Color color,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final entry = widget.entry;
    final labels = [
      auditEventLabel(l10n, entry.eventType, entry.rawEventType),
      ...contextLabels,
    ];
    final date = grantRelativeTime(l10n, entry.occurredAt);
    final dateStyle = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(fontSize: 11, inherit: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: date, style: dateStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final dateWidth = (painter.width.ceilToDouble() + 1).clamp(
          0.0,
          constraints.maxWidth * 0.4,
        );
        painter.dispose();
        final available =
            constraints.maxWidth - dateWidth - AppSpacing.innerGap;
        final widths = labels
            .map((label) => StatusBadge.naturalWidth(context, label))
            .toList();
        var visible = labels.length;
        double needed(int count) =>
            widths.take(count).fold(0.0, (sum, width) => sum + width) +
            AppSpacing.chipGap * (count - 1);
        while (visible > 1 &&
            needed(visible) +
                    (visible < labels.length ? 32 + AppSpacing.chipGap : 0) >
                available) {
          visible--;
        }
        final hidden = labels.length - visible;
        final chipSpace =
            available - (hidden > 0 ? 32 + AppSpacing.chipGap : 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      for (var i = 0; i < visible; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.chipGap),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: visible == 1
                                ? chipSpace.clamp(0.0, double.infinity)
                                : double.infinity,
                          ),
                          child: StatusBadge(
                            label: labels[i],
                            color: i == 0
                                ? color
                                : AppColors.onSurfaceMuted(brightness),
                          ),
                        ),
                      ],
                      if (hidden > 0) ...[
                        const SizedBox(width: AppSpacing.chipGap),
                        SizedBox(
                          width: 32,
                          child: Tooltip(
                            message: _chipsExpanded
                                ? l10n.entryShowLess
                                : l10n.entryShowMore,
                            child: TextButton(
                              onPressed: () => setState(
                                () => _chipsExpanded = !_chipsExpanded,
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.onSurfaceMuted(
                                  brightness,
                                ),
                                minimumSize: const Size(32, 32),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: _chipsExpanded
                                  ? const Icon(Icons.expand_less, size: 16)
                                  : Text(
                                      '+$hidden',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.innerGap),
                SizedBox(
                  width: dateWidth,
                  child: Tooltip(
                    message: auditTimestamp(
                      entry.occurredAt,
                      Localizations.localeOf(context).toString(),
                    ),
                    child: Text(
                      date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: dateStyle.copyWith(
                        color: AppColors.onSurfaceSubtle(brightness),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_chipsExpanded && hidden > 0) ...[
              const SizedBox(height: AppSpacing.chipGap),
              Wrap(
                spacing: AppSpacing.chipGap,
                runSpacing: AppSpacing.chipGap,
                children: [
                  for (final label in labels.skip(visible))
                    StatusBadge(
                      label: label,
                      color: AppColors.onSurfaceMuted(brightness),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  /// Builds the composed sentence as a [TextSpan], emphasising the marked
  /// name runs (actor / object) in bold — matching the web panel.
  TextSpan _sentenceText(
    List<AuditSentenceSpan> spans,
    Brightness brightness,
    String actor,
  ) {
    return TextSpan(
      style: TextStyle(
        color: AppColors.onSurfaceMuted(brightness),
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      children: [
        for (final span in spans)
          TextSpan(
            text: span.text,
            style: span.bold
                ? TextStyle(
                    fontWeight: span.text == actor
                        ? FontWeight.w400
                        : FontWeight.w600,
                    color: span.text == actor
                        ? AppColors.onSurfaceMuted(brightness)
                        : AppColors.onSurface(brightness),
                  )
                : null,
          ),
      ],
    );
  }
}

class _ExpandedDetail extends StatelessWidget {
  const _ExpandedDetail({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    final rows = <(String, String)>[
      if (entry.resolvedVaultName != null &&
          entry.resolvedVaultName!.isNotEmpty)
        (l10n.auditDetailVault, entry.resolvedVaultName!),
      if (entry.entryLabel != null && entry.entryLabel!.isNotEmpty)
        (l10n.auditDetailEntry, entry.entryLabel!),
      if (entry.entryCurrentLogin != null)
        (l10n.auditDetailCurrentLogin, entry.entryCurrentLogin!),
      if (entry.agentReason != null && entry.agentReason!.isNotEmpty)
        (l10n.auditDetailReason, entry.agentReason!),
      ...entry.metadata.entries
          .where((e) => e.value.isNotEmpty)
          .map(
            (e) => (
              e.key == 'shareId' ? l10n.auditDetailSharing : e.key,
              auditMetadataValue(e.key, e.value),
            ),
          ),
    ];

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Text(
          l10n.auditDetailNone,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 11,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: AppColors.cardBorder(brightness)),
          const SizedBox(height: AppSpacing.md),
          for (final (key, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      key,
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: AppColors.onSurfaceMuted(brightness),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
