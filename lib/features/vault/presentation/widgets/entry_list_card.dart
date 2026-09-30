import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/member_index_entry.dart';
import 'entry_field_row.dart';
import 'entry_list_icon.dart';

class EntryListCard extends StatelessWidget {
  const EntryListCard({
    super.key,
    required this.entry,
    required this.isExpanded,
    required this.payload,
    required this.revealedFields,
    required this.onToggleReveal,
    required this.onToggleFieldReveal,
    required this.onCopy,
    required this.onEdit,
    this.onShare,
    this.vaultName,
    this.enabled = true,
  });

  final EntryEntity entry;
  final bool isExpanded;
  final Map<String, dynamic>? payload;
  final Set<String> revealedFields;
  final VoidCallback onToggleReveal;
  final void Function(String entryId, String field) onToggleFieldReveal;
  final ValueChanged<String> onCopy;
  final VoidCallback onEdit;
  final VoidCallback? onShare;
  final String? vaultName;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final interactive =
        enabled &&
        entry.lifecycleState == MemberEntryState.active &&
        !entry.corrupt;
    final meta = entry.corrupt
        ? l10n.entryCorruptProjection
        : switch (entry.lifecycleState) {
            MemberEntryState.active =>
              vaultName ?? entry.urlDomain ?? entry.description ?? '',
            MemberEntryState.archived => l10n.entryArchivedRecoverability,
            MemberEntryState.deleted => l10n.entryDeletedRecoverability,
            MemberEntryState.unknown => l10n.responseUnknownValue,
          };

    return Material(
      color: AppColors.transparent,
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
                    EntryListIcon(entry: entry),
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
                      if (onShare != null) ...[
                        const SizedBox(width: AppSpacing.chipGap),
                        EntrySmallIconButton(
                          icon: Icons.share_outlined,
                          tooltip: l10n.sharingShareEntry,
                          onPressed: onShare!,
                        ),
                      ],
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
        ] else if (entry.type == EntryType.creditCard) ...[
          for (final cardField in <(String, IconData, bool)>[
            ('cardholderName', Icons.person, false),
            ('cardNumber', Icons.credit_card, true),
            ('expiryMonth', Icons.calendar_month, false),
            ('expiryYear', Icons.event, false),
            ('billingAddress', Icons.home, false),
          ])
            if ((payload[cardField.$1] as String?)?.isNotEmpty ?? false)
              EntryFieldRow(
                icon: cardField.$2,
                value: payload[cardField.$1] as String,
                isMasked: cardField.$3,
                revealed:
                    !cardField.$3 ||
                    revealedFields.contains('${entry.id}:${cardField.$1}'),
                onToggleReveal: cardField.$3
                    ? () => onToggleFieldReveal(entry.id, cardField.$1)
                    : null,
                valueFontSize: 10,
                actionIconSize: 12,
                onCopy: () => onCopy(payload[cardField.$1] as String),
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
