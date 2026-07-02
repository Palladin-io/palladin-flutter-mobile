import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../audit_log_format.dart';

/// A single expandable audit log row.
///
/// Collapsed: a color-coded left accent bar, the event sentence/label, and a
/// footer with the timestamp + expand chevron. Tapping expands to reveal the
/// entry label, the agent's reason and any non-sensitive metadata (grant id,
/// method, ip, device…). All values are metadata only — never secrets.
class AuditLogRow extends StatefulWidget {
  const AuditLogRow({super.key, required this.entry, required this.agentNames});

  final AuditLogEntry entry;
  final Map<String, String> agentNames;

  @override
  State<AuditLogRow> createState() => _AuditLogRowState();
}

class _AuditLogRowState extends State<AuditLogRow> {
  bool _expanded = false;

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

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      // Clip so the left accent bar's corners follow the card's radius.
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Stack(
            children: [
              // Color-coded left accent bar (severity), spanning the full row
              // height — replaces the previous status dot.
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: color),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sentence != null)
                      Text.rich(
                        _sentenceText(sentence, brightness),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      )
                    else ...[
                      Text(
                        auditEventLabel(
                          l10n,
                          entry.eventType,
                          entry.rawEventType,
                        ),
                        style: TextStyle(
                          color: AppColors.onSurface(brightness),
                          fontSize: 13,
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
                    // Footer under the content — just the timestamp, right-
                    // aligned and subtle. The whole row is tap-to-expand, so no
                    // chevron indicator is needed.
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          auditTimestamp(
                            entry.createdAt,
                            Localizations.localeOf(context).toString(),
                          ),
                          style: TextStyle(
                            color: AppColors.onSurfaceSubtle(brightness),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    if (_expanded) _ExpandedDetail(entry: entry),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the composed sentence as a [TextSpan], emphasising the marked
  /// name runs (actor / object) in bold — matching the web panel.
  TextSpan _sentenceText(List<AuditSentenceSpan> spans, Brightness brightness) {
    return TextSpan(
      style: TextStyle(
        color: AppColors.onSurface(brightness),
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w400,
      ),
      children: [
        for (final span in spans)
          TextSpan(
            text: span.text,
            style: span.bold
                ? const TextStyle(fontWeight: FontWeight.w700)
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
      if (entry.entryLabel != null && entry.entryLabel!.isNotEmpty)
        (l10n.auditDetailEntry, entry.entryLabel!),
      if (entry.agentReason != null && entry.agentReason!.isNotEmpty)
        (l10n.auditDetailReason, entry.agentReason!),
      ...entry.metadata.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => (e.key, e.value)),
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
