import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';

class EntryShareFieldCard extends StatefulWidget {
  const EntryShareFieldCard({
    super.key,
    required this.label,
    required this.type,
    required this.value,
    this.enabled = true,
    this.beforeReveal,
    this.trailing,
  });
  final String label, type, value;
  final bool enabled;
  final Future<bool> Function()? beforeReveal;
  final Widget? trailing;

  @override
  State<EntryShareFieldCard> createState() => _EntryShareFieldCardState();
}

class _EntryShareFieldCardState extends State<EntryShareFieldCard> {
  bool _revealed = false;
  bool _checking = false;
  int _generation = 0;

  @override
  void didUpdateWidget(EntryShareFieldCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.type != widget.type ||
        oldWidget.label != widget.label) {
      _generation++;
      _revealed = false;
      _checking = false;
    }
  }

  Future<void> _toggle() async {
    if (_checking || !widget.enabled) return;
    if (_revealed) {
      setState(() => _revealed = false);
      return;
    }
    _checking = true;
    final generation = _generation;
    try {
      final allowed = await widget.beforeReveal?.call() ?? true;
      if (mounted && generation == _generation && allowed && widget.enabled) {
        setState(() => _revealed = true);
      }
    } catch (_) {
      // A failed authority check must never reveal the field.
    } finally {
      if (generation == _generation) _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final sensitive = widget.type == 'concealed' || widget.type == 'totp';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        border: Border.all(color: AppColors.cardBorder(brightness)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface(brightness),
                  ),
                ),
              ),
              if (sensitive)
                IconButton(
                  tooltip: _revealed
                      ? l10n.sharingHidePreview
                      : l10n.vaultRevealValue,
                  onPressed: widget.enabled ? _toggle : null,
                  icon: Icon(
                    _revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: AppColors.onSurfaceSubtle(brightness),
                  ),
                ),
              if (widget.trailing != null) ...[
                const SizedBox(width: AppSpacing.innerGap),
                widget.trailing!,
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.innerGap),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(
                sensitive && !_revealed ? '••••••••' : widget.value,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.onSurfaceSubtle(brightness),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
