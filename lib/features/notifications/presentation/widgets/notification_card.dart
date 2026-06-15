import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../grants/presentation/widgets/org_grant_card.dart' show GrantDetailRow;
import '../../domain/entities/inbox_notification.dart';
import 'notification_format.dart';

/// Grant-style notification card (ported from the web prototype
/// `notification-center-variants.html`): an avatar/icon header with name +
/// subtitle + relative time, a divided rows section, and a footer.
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
    final accent = notificationAccent(item);
    final rows = notificationRows(l10n, item);
    final hasFooter =
        onPrimary != null || onSecondary != null || footerNote != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isRead
              ? AppColors.cardBorder(brightness)
              : accent.withValues(alpha: 0.55),
        ),
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
                    accent: accent,
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
                accent: accent,
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
    required this.accent,
    required this.statusPill,
  });

  final InboxNotification item;
  final Color accent;
  final ({String label, Color color})? statusPill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final subtitle = notificationSubtitle(l10n, item);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.14),
          ),
          child: Icon(notificationIcon(item), size: 16, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      notificationTitle(l10n, item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 13,
                        fontWeight:
                            item.isRead ? FontWeight.w600 : FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!item.isRead)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: const BoxDecoration(
                        color: AppColors.brandRed,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
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
        if (statusPill != null)
          _StatusPill(label: statusPill!.label, color: statusPill!.color)
        else
          Text(
            notificationRelativeTime(l10n, item),
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 10,
            ),
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

class _Footer extends StatelessWidget {
  const _Footer({
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.footerNote,
    required this.accent,
    required this.isBusy,
  });

  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? footerNote;
  final Color accent;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFooterOverlay(brightness),
        border: Border(top: BorderSide(color: AppColors.cardBorder(brightness))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: OutlinedButton(
                        onPressed: isBusy ? null : onSecondary,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.onSurfaceMuted(brightness),
                          side: BorderSide(
                            color: AppColors.cardBorder(brightness),
                          ),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          secondaryLabel ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (onPrimary != null)
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: FilledButton(
                        onPressed: isBusy ? null : onPrimary,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
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
                    ),
                  ),
              ],
            ),
    );
  }
}
