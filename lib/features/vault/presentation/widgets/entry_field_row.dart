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
    this.multiline = false,
    this.valueFontSize = 12,
    this.actionIconSize = 14,
  });

  final IconData icon;
  final String value;

  /// When true the value is hidden behind bullets until [revealed] flips.
  final bool isMasked;
  final bool revealed;

  /// Null hides the eye toggle (non-secret fields are always visible).
  final VoidCallback? onToggleReveal;
  final VoidCallback onCopy;
  final Widget? extraTrailing;
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
    final displayed = isMasked && !revealed ? '••••••••••••' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 12, color: AppColors.onSurfaceSubtle(brightness)),
          const SizedBox(width: AppSpacing.innerGap),
          Expanded(
            child: multiline
                ? _ExpandableValueText(
                    value: displayed,
                    fontSize: valueFontSize,
                    brightness: brightness,
                  )
                : Text(
                    displayed,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: valueFontSize,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
          if (onToggleReveal != null)
            EntrySmallIconButton(
              icon: revealed ? Icons.visibility_off : Icons.visibility,
              size: actionIconSize,
              tooltip: l10n.vaultRevealValue,
              onPressed: onToggleReveal!,
            ),
          if (onToggleReveal != null) const SizedBox(width: AppSpacing.xs),
          EntrySmallIconButton(
            icon: Icons.content_copy,
            size: actionIconSize,
            tooltip: l10n.vaultCopyValue,
            onPressed: onCopy,
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
  });

  final String value;
  final double fontSize;
  final Brightness brightness;

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
      fontFamily: 'monospace',
      letterSpacing: 0.5,
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
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Icon(
            icon,
            size: size,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
        ),
      ),
    );
  }
}
