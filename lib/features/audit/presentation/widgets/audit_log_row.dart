import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../audit_log_format.dart';

/// A single expandable audit log row.
///
/// Collapsed: colored event dot, event label, actor name and timestamp.
/// Tapping expands to reveal the entry label, the agent's reason and any
/// non-sensitive metadata (grant id, method, ip, device…). All values are
/// metadata only — never secrets.
class AuditLogRow extends StatefulWidget {
  const AuditLogRow({
    super.key,
    required this.entry,
    required this.agentNames,
  });

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
    final actor = auditActorName(l10n, entry, widget.agentNames);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.innerGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                      ),
                    ),
                    const SizedBox(width: AppSpacing.innerGap),
                    Text(
                      auditTimestamp(entry.createdAt),
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: AppColors.onSurfaceSubtle(brightness),
                    ),
                  ],
                ),
                if (_expanded) _ExpandedDetail(entry: entry),
              ],
            ),
          ),
        ),
      ),
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
