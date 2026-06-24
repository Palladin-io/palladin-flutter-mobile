import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../agents/presentation/widgets/agent_avatar.dart';
import '../../../grants/presentation/widgets/org_grant_card.dart' show GrantDetailRow;
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
        const SizedBox(width: AppSpacing.innerGap),
        // Date sits top-right on the title line. No status pill — the card is
        // an immutable log entry, so it carries no live state indicator.
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
  static const double _buttonHeight = 36;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasInlineActions = onPrimary != null || onSecondary != null;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFooterOverlay(brightness),
        border: Border(top: BorderSide(color: AppColors.cardBorder(brightness))),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.innerGap,
      ),
      // Pin a consistent footer min-height so action + log cards align.
      constraints: const BoxConstraints(minHeight: _buttonHeight + 16),
      child: hasInlineActions
          ? Row(
              children: [
                if (onSecondary != null) ...[
                  Expanded(child: _secondaryButton(brightness)),
                  const SizedBox(width: AppSpacing.innerGap),
                ],
                if (onPrimary != null) Expanded(child: _primaryButton()),
              ],
            )
          : _viewLink(brightness),
    );
  }

  Widget _viewLink(Brightness brightness) {
    return SizedBox(
      height: _buttonHeight,
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onView,
        icon: const Icon(
          Icons.open_in_new,
          size: 14,
          color: AppColors.brandRed,
        ),
        label: Text(
          viewLabel ?? '',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brandRed,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
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
            : Text(
                primaryLabel ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
