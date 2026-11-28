import '../../../../core/widgets/card_action_footer.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../agents/presentation/widgets/agent_avatar.dart';
import '../../../grants/presentation/widgets/org_grant_card.dart'
    show GrantDetailRow;
import '../../domain/entities/inbox_notification.dart';
import 'notification_format.dart';

/// A notification card — an **immutable event log entry**, not a live control
/// panel: an avatar/icon header with name + subtitle, the relative time
/// top-right on the title line, a divided rows section, and a footer.
///
/// All cards share a single uniform border + background (`AppColors.cardFill`
/// / `cardBorder`) — no per-type accent border, no status pill and no unread
/// dot, so the feed stays visually even.
///
/// The footer adapts to the item:
/// - Action-required PENDING (grant_pending / agent_pending): inline
///   Approve / Deny buttons — the only cards that mutate state.
/// - Everything else (resolved / informational): a single "View" link that
///   deep-links to the owning surface. No footer at all when there is no
///   deep-link target.
class NotificationCard extends StatelessWidget {
  const NotificationCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onPrimary,
    this.onSecondary,
    this.primaryLabel,
    this.secondaryLabel,
    this.primaryTone = NotificationPrimaryTone.positive,
    this.onView,
    this.viewLabel,
    this.isBusy = false,
  });

  final InboxNotification item;
  final VoidCallback onTap;

  /// Primary footer button (Approve). Text-only — no icon, to avoid an
  /// icon/text mix across the footer actions.
  final VoidCallback? onPrimary;
  final String? primaryLabel;

  /// Background tone of the primary action (positive = teal, danger = red).
  final NotificationPrimaryTone primaryTone;

  /// Secondary footer button (Deny).
  final VoidCallback? onSecondary;
  final String? secondaryLabel;

  /// Single non-mutating "View" footer link for resolved/informational cards.
  /// When set (and no inline actions are), the footer renders just this link.
  final VoidCallback? onView;
  final String? viewLabel;

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final glyphTint = notificationGlyphTint(item);
    final rows = notificationRows(l10n, item);
    final hasFooter =
        onPrimary != null || onSecondary != null || onView != null;

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
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.cardPadding,
                    AppSpacing.md,
                    AppSpacing.cardPadding,
                    AppSpacing.md,
                  ),
                  child: _Header(item: item, glyphTint: glyphTint),
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.cardPadding,
                  AppSpacing.md,
                  AppSpacing.cardPadding,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.innerGap),
                      GrantDetailRow(
                        label: rows[i].label,
                        value: rows[i].value,
                        maxLines: item.type == 'entry_share_received'
                            ? null
                            : 1,
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (hasFooter)
              _Footer(
                primaryLabel: primaryLabel,
                onPrimary: onPrimary,
                secondaryLabel: secondaryLabel,
                onSecondary: onSecondary,
                onView: onView,
                viewLabel: viewLabel,
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
  const _Header({required this.item, required this.glyphTint});

  final InboxNotification item;
  final Color glyphTint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final subtitle = notificationSubtitle(l10n, item);
    final isSharingReceipt = item.type == 'entry_share_received';
    final timestamp = Text(
      notificationRelativeTime(l10n, item),
      style: TextStyle(
        color: AppColors.onSurfaceSubtle(brightness),
        fontSize: 10,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Agent-bearing cards use the real Agents-list avatar (glyph/image +
        // deterministic tint) so the icon and color match the Agents screen;
        // non-agent cards (credential_stale) keep a tinted glyph chip.
        if (notificationUsesAgentAvatar(item))
          AgentAvatar(
            agentId: notificationAgentId(item),
            name: notificationAgentName(item),
            iconKey: notificationAgentIconKey(item),
            iconColor: notificationAgentIconColor(item),
            size: 36,
          )
        else
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: glyphTint.withValues(alpha: 0.14),
            ),
            child: Icon(notificationIcon(item), size: 18, color: glyphTint),
          ),
        const SizedBox(width: AppSpacing.innerGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                notificationTitle(l10n, item),
                maxLines: isSharingReceipt ? null : 1,
                overflow: isSharingReceipt
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  maxLines: isSharingReceipt ? null : 1,
                  overflow: isSharingReceipt
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontSize: 11,
                  ),
                ),
              ],
              if (isSharingReceipt) ...[
                const SizedBox(height: AppSpacing.innerGap),
                timestamp,
              ],
            ],
          ),
        ),
        if (!isSharingReceipt) ...[
          const SizedBox(width: AppSpacing.innerGap),
          timestamp,
        ],
      ],
    );
  }
}

/// Tone of the primary footer action — drives its background color.
enum NotificationPrimaryTone { positive, danger }

class _Footer extends StatelessWidget {
  const _Footer({
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.onView,
    required this.viewLabel,
    required this.primaryTone,
    required this.isBusy,
  });

  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final VoidCallback? onView;
  final String? viewLabel;
  final NotificationPrimaryTone primaryTone;
  final bool isBusy;

  /// Fixed height for every footer slot so buttons line up across cards
  /// regardless of whether they carry a leading icon.
  static const double _buttonHeight = AppSpacing.controlHeight;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasInlineActions = onPrimary != null || onSecondary != null;
    return CardActionFooter(
      child: hasInlineActions
          ? Row(
              children: [
                if (onSecondary != null) ...[
                  Expanded(child: _secondaryButton(brightness)),
                  if (onPrimary != null)
                    SizedBox(
                      height: _buttonHeight,
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: AppColors.cardBorder(brightness),
                      ),
                    ),
                ],
                if (onPrimary != null) Expanded(child: _primaryButton()),
              ],
            )
          : _viewLink(brightness),
    );
  }

  Widget _viewLink(Brightness brightness) => _action(
    label: viewLabel ?? '',
    icon: Icons.open_in_new,
    color: AppColors.brandRed,
    onPressed: onView,
  );

  Widget _secondaryButton(Brightness brightness) => _action(
    label: secondaryLabel ?? '',
    icon: Icons.close,
    color: AppColors.onSurfaceMuted(brightness),
    onPressed: isBusy ? null : onSecondary,
  );

  Widget _primaryButton() => _action(
    label: primaryLabel ?? '',
    icon: Icons.check,
    color: primaryTone == NotificationPrimaryTone.positive
        ? AppColors.positiveAccent
        : AppColors.brandRed,
    onPressed: isBusy ? null : onPrimary,
    loading: isBusy,
  );

  Widget _action({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    return CardFooterAction(
      label: label,
      icon: icon,
      color: color,
      onPressed: onPressed,
      loading: loading,
    );
  }
}
