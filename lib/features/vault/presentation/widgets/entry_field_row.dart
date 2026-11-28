import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// A single revealed-field row: leading glyph, the (optionally masked)
/// value, an optional reveal toggle, a copy action, and optional extra
/// trailing controls (e.g. an "open URL" button).
///
/// Extracted from the entries-tab reveal panel so the read-only entry
/// detail view renders secrets with the exact same masked-value + copy
/// visual — a single source of truth for the "reveal row" idiom.
class EntryFieldRow extends StatelessWidget {
  const EntryFieldRow({
    super.key,
    required this.icon,
    required this.value,
    required this.isMasked,
    required this.revealed,
    required this.onToggleReveal,
    required this.onCopy,
    this.extraTrailing,
    this.beforeActions,
    this.label,
    this.multiline = false,
    this.valueFontSize = 12,
    this.actionIconSize = 14,
  });

  final String? label;

  EntryFieldRow labeled(String text) => EntryFieldRow(
    icon: icon,
    value: value,
    isMasked: isMasked,
    revealed: revealed,
    onToggleReveal: onToggleReveal,
    onCopy: onCopy,
    extraTrailing: extraTrailing,
    beforeActions: beforeActions,
    multiline: multiline,
    label: text,
    valueFontSize: 14,
    actionIconSize: 18,
  );

  final IconData icon;
  final String value;

  /// When true the value is hidden behind bullets until [revealed] flips.
  final bool isMasked;
  final bool revealed;

  /// Null hides the eye toggle (non-secret fields are always visible).
  final VoidCallback? onToggleReveal;

  /// Null hides the copy action (status rows without a copyable value).
  final VoidCallback? onCopy;
  final Widget? extraTrailing;
  final Widget? beforeActions;
  final bool multiline;

  /// Font size of the value text. Defaults to 12 (entry detail); the
  /// denser entries-tab reveal panel passes 10.
  final double valueFontSize;

  /// Size of the trailing reveal/copy glyphs.
  final double actionIconSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final displayed = value.isEmpty
        ? '—'
        : isMasked && !revealed
        ? '••••••••••••'
        : value;
    return Padding(
      padding: label == null
          ? const EdgeInsets.symmetric(vertical: AppSpacing.xs)
          : const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
      child: Row(
        children: [
          const SizedBox(height: AppSpacing.controlHeight),
          if (label == null) ...[
            Icon(icon, size: 12, color: AppColors.onSurfaceSubtle(brightness)),
            const SizedBox(width: AppSpacing.innerGap),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) ...[
                  Text(
                    label!,
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                if (multiline)
                  _ExpandableValueText(
                    value: displayed,
                    fontSize: valueFontSize,
                    brightness: brightness,
                    monospace: label == null,
                  )
                else
                  Text(
                    displayed,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: valueFontSize,
                      fontFamily: label == null ? 'monospace' : null,
                      letterSpacing: label == null ? 0.5 : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.innerGap),
          if (beforeActions != null) ...[
            beforeActions!,
            const SizedBox(width: AppSpacing.xs),
          ],
          if (value.isNotEmpty && onToggleReveal != null)
            EntrySmallIconButton(
              icon: revealed ? Icons.visibility_off : Icons.visibility,
              size: actionIconSize,
              tooltip: l10n.vaultRevealValue,
              onPressed: onToggleReveal!,
            ),
          if (value.isNotEmpty && onToggleReveal != null && onCopy != null)
            const SizedBox(width: AppSpacing.xs),
          if (value.isNotEmpty && onCopy != null)
            EntrySmallIconButton(
              icon: Icons.content_copy,
              size: actionIconSize,
              tooltip: l10n.vaultCopyValue,
              onPressed: onCopy!,
            ),
          if (extraTrailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            extraTrailing!,
          ],
        ],
      ),
    );
  }
}

class _ExpandableValueText extends StatefulWidget {
  const _ExpandableValueText({
    required this.value,
    required this.fontSize,
    required this.brightness,
    required this.monospace,
  });

  final String value;
  final double fontSize;
  final Brightness brightness;
  final bool monospace;

  @override
  State<_ExpandableValueText> createState() => _ExpandableValueTextState();
}

class _ExpandableValueTextState extends State<_ExpandableValueText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final style = TextStyle(
      color: AppColors.onSurface(widget.brightness),
      fontSize: widget.fontSize,
      fontFamily: widget.monospace ? 'monospace' : null,
      letterSpacing: widget.monospace ? 0.5 : null,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.value, style: style),
          textDirection: Directionality.of(context),
          maxLines: 3,
        )..layout(maxWidth: constraints.maxWidth);
        final truncated = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.value,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: style,
            ),
            if (truncated || _expanded)
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _expanded ? l10n.entryShowLess : l10n.entryShowMore,
                    style: TextStyle(
                      color: AppColors.brandRed,
                      fontSize: widget.fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Compact tappable icon used for the reveal / copy / open row actions.
class EntrySmallIconButton extends StatelessWidget {
  const EntrySmallIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 14,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 16,
        child: SizedBox.square(
          dimension: AppSpacing.controlHeight,
          child: Center(
            child: Icon(
              icon,
              size: size,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
          ),
        ),
      ),
    );
  }
}
