import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../audit_log_format.dart';

/// A single expandable audit log row.
///
/// Collapsed: colored event dot, event sentence/label, optional vault chip,
/// and timestamp. Tapping expands to reveal the entry label, the agent's
/// reason and any non-sensitive metadata (grant id, method, ip, device…).
/// All values are metadata only — never secrets.
class AuditLogRow extends StatefulWidget {
  const AuditLogRow({
    super.key,
    required this.entry,
    required this.agentNames,
    this.vaultNames = const {},
    this.showVaultChip = false,
  });

  final AuditLogEntry entry;
  final Map<String, String> agentNames;

  /// Resolved vault id → name, used to label the vault chip. Reuses the
  /// cubit's vault-name resolution (org scope) — no extra lookup.
  final Map<String, String> vaultNames;

  /// Whether to show the vault chip. Only the org-wide Logs screen sets this;
  /// the per-vault tab leaves it off (the vault is implicit there).
  final bool showVaultChip;

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
    // Vault chip (org scope only): show which vault the event happened in when
    // the vault id resolves to a known name. Unknown name → no chip.
    final vaultId = entry.vaultId;
    final vaultName = widget.showVaultChip && vaultId != null
        ? widget.vaultNames[vaultId]?.trim()
        : null;
    final showVaultChip = vaultName != null && vaultName.isNotEmpty;

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
                        mainAxisSize: MainAxisSize.min,
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
                          if (showVaultChip) ...[
                            const SizedBox(height: AppSpacing.innerGap),
                            _VaultChip(
                              name: vaultName,
                              brightness: brightness,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.innerGap),
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

/// Compact, read-only pill showing the vault an org-wide audit event happened
/// in. Shield icon + vault name; same surface/border tokens as the row card.
class _VaultChip extends StatelessWidget {
  const _VaultChip({required this.name, required this.brightness});

  final String name;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardSurface(brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 12,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                color: AppColors.onSurfaceMuted(brightness),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
