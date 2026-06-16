import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../grants/presentation/widgets/org_grant_card.dart' show GrantDetailRow;
import '../../domain/entities/inbox_notification.dart';
import 'notification_format.dart';

/// Grant-style notification card (parity with the web `NotificationCard`):
/// an avatar/icon header with name + subtitle, the relative time top-right on
/// the title line with the optional status pill stacked **under** the date, a
/// divided rows section, and a footer.
///
/// All cards share a single uniform border + background (`AppColors.cardFill`
/// / `cardBorder`) — no per-type accent border and no unread dot, so the feed
/// stays visually even. The footer pins a consistent min-height so action and
/// history cards line up.
///
/// The footer adapts to the item:
/// - To-do (open action): per-type primary + secondary buttons.
/// - History (resolved): a status pill in the header and a single
///   contextual action (revoke / re-grant / "active access" note).
class NotificationCard extends StatelessWidget {
  const NotificationCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onPrimary,
    this.onSecondary,
    this.primaryLabel,
    this.secondaryLabel,
    this.primaryIcon,
    this.primaryTone = NotificationPrimaryTone.positive,
    this.statusPill,
    this.footerNote,
    this.isBusy = false,
  });

  final InboxNotification item;
  final VoidCallback onTap;

  /// Primary footer button (e.g. Approve / Update / Re-grant).
  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final IconData? primaryIcon;

  /// Background tone of the primary action (positive = teal, danger = red).
  final NotificationPrimaryTone primaryTone;

  /// Secondary footer button (e.g. Deny / Skip).
  final VoidCallback? onSecondary;
  final String? secondaryLabel;

  /// Header status pill for History items (label, color).
  final ({String label, Color color})? statusPill;

  /// Centered footer note (e.g. "Agent has active access").
  final String? footerNote;

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final glyphTint = notificationGlyphTint(item);
    final rows = notificationRows(l10n, item);
    final hasFooter =
        onPrimary != null || onSecondary != null || footerNote != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        // Uniform card chrome for every type/state — no accent border, no
        // unread dot. Keeps the feed visually even.
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: _Header(
                    item: item,
                    glyphTint: glyphTint,
                    statusPill: statusPill,
                  ),
                ),
              ),
            ),
            if (rows.isNotEmpty) ...[
              Divider(
                height: 1,
                thickness: 1,
                color: AppColors.cardBorder(brightness),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      GrantDetailRow(
                        label: rows[i].label,
                        value: rows[i].value,
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (hasFooter)
              _Footer(
                primaryLabel: primaryLabel,
                primaryIcon: primaryIcon,
                onPrimary: onPrimary,
                secondaryLabel: secondaryLabel,
                onSecondary: onSecondary,
                footerNote: footerNote,
                primaryTone: primaryTone,
                isBusy: isBusy,
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.glyphTint,
    required this.statusPill,
  });

  final InboxNotification item;
  final Color glyphTint;
  final ({String label, Color color})? statusPill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final subtitle = notificationSubtitle(l10n, item);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: glyphTint.withValues(alpha: 0.14),
          ),
          child: Icon(notificationIcon(item), size: 16, color: glyphTint),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                notificationTitle(l10n, item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Date sits top-right on the title line; the status pill (if any)
        // stacks directly under the date — never inline with the title.
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              notificationRelativeTime(l10n, item),
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 10,
              ),
            ),
            if (statusPill != null) ...[
              const SizedBox(height: 6),
              _StatusPill(label: statusPill!.label, color: statusPill!.color),
            ],
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tone of the primary footer action — drives its background color.
enum NotificationPrimaryTone { positive, danger }

class _Footer extends StatelessWidget {
  const _Footer({
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.footerNote,
    required this.primaryTone,
    required this.isBusy,
  });

  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? footerNote;
  final NotificationPrimaryTone primaryTone;
  final bool isBusy;

  /// Fixed height for every footer slot so buttons line up across cards
  /// regardless of whether they carry a leading icon.
  static const double _buttonHeight = 36;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFooterOverlay(brightness),
        border: Border(top: BorderSide(color: AppColors.cardBorder(brightness))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      // Pin a consistent footer min-height so action + history cards align.
      constraints: const BoxConstraints(minHeight: _buttonHeight + 16),
      child: footerNote != null
          ? Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 14,
                    color: AppColors.positiveAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    footerNote!,
                    style: const TextStyle(
                      color: AppColors.positiveAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                if (onSecondary != null) ...[
                  Expanded(child: _secondaryButton(brightness)),
                  const SizedBox(width: 8),
                ],
                if (onPrimary != null) Expanded(child: _primaryButton()),
              ],
            ),
    );
  }

  Widget _secondaryButton(Brightness brightness) {
    return SizedBox(
      height: _buttonHeight,
      child: OutlinedButton(
        onPressed: isBusy ? null : onSecondary,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurfaceMuted(brightness),
          side: BorderSide(color: AppColors.cardBorder(brightness)),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          secondaryLabel ?? '',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _primaryButton() {
    final background = switch (primaryTone) {
      NotificationPrimaryTone.positive => AppColors.positiveAccent,
      NotificationPrimaryTone.danger => AppColors.brandRed,
    };
    return SizedBox(
      height: _buttonHeight,
      child: FilledButton(
        onPressed: isBusy ? null : onPrimary,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: AppColors.onBrandRed,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: isBusy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onBrandRed,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (primaryIcon != null) ...[
                    Icon(primaryIcon, size: 14),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    primaryLabel ?? '',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
