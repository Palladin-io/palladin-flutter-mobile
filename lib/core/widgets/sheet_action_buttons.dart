import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Standard Cancel + Confirm footer for modal bottom sheets.
///
/// Renders a full-width tinted footer band (top hairline + soft fill, like the
/// web `DialogFooter`) with a Cancel + Confirm row. One place owns the band,
/// the button height (44) and the 1:2 width ratio so every sheet (approve /
/// deny / revoke …) looks identical — no more "one taller, one shorter" drift.
/// The band absorbs the bottom safe-area and keyboard inset itself, so callers
/// place it flush at the bottom of the sheet (no bottom padding of their own).
class SheetActionButtons extends StatelessWidget {
  const SheetActionButtons({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
    required this.confirmColor,
    this.cancelLabel,
    this.busy = false,
  });

  /// Tapped on the Cancel button. Pass `null` while [busy] to disable it.
  final VoidCallback? onCancel;

  /// Tapped on the Confirm button. Pass `null` while [busy] to disable it.
  final VoidCallback? onConfirm;

  final String confirmLabel;
  final Color confirmColor;

  /// Defaults to the shared "Cancel" string when omitted.
  final String? cancelLabel;

  /// Shows a spinner on Confirm and disables both buttons.
  final bool busy;

  static const double _height = 44;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final safeBottom = MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardFooterOverlay(brightness),
        border: Border(
          top: BorderSide(color: AppColors.cardBorder(brightness)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.cardPadding,
        AppSpacing.screenH,
        AppSpacing.cardPadding + safeBottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: _height,
              child: OutlinedButton(
                onPressed: busy ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurfaceMuted(brightness),
                  side: BorderSide(color: AppColors.cardBorder(brightness)),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  cancelLabel ?? l10n.approvalCancel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: _height,
              child: FilledButton(
                onPressed: busy ? null : onConfirm,
                style: FilledButton.styleFrom(
                  backgroundColor: confirmColor,
                  foregroundColor: AppColors.onBrandRed,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onBrandRed,
                        ),
                      )
                    : Text(
                        confirmLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
