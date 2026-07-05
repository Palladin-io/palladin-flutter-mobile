import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'sheet_drag_handle.dart';

/// One row in an [showAppMenuSheet] action sheet.
class AppMenuItem<T> {
  const AppMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.trailing,
    this.trailingColor,
    this.danger = false,
    this.dividerBefore = false,
  });

  final T value;
  final IconData icon;
  final String label;

  /// Optional muted trailing hint (e.g. the current selection).
  final String? trailing;
  final Color? trailingColor;

  /// Renders the row in the danger tone (destructive action).
  final bool danger;

  /// Draws a hairline separator above this row (group boundary).
  final bool dividerBefore;
}

/// Shows a native-style bottom-sheet action menu — the mobile counterpart
/// of the web "⋯" popover. Returns the chosen item's value, or null when
/// dismissed. Reused by the additional-fields add/row menus and the 2FA
/// card menu.
Future<T?> showAppMenuSheet<T>({
  required BuildContext context,
  String? title,
  required List<AppMenuItem<T>> items,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final brightness = Theme.of(sheetContext).brightness;
      return Container(
        decoration: BoxDecoration(
          color: AppColors.modalBackground(brightness),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Center(child: SheetDragHandle()),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    AppSpacing.xs,
                    AppSpacing.screenH,
                    AppSpacing.sm,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: TextStyle(
                        color: AppColors.onSurfaceSubtle(brightness),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              for (final item in items) ...[
                if (item.dividerBefore)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.onSurface(brightness)
                        .withValues(alpha: 0.06),
                  ),
                _MenuRow(
                  item: item,
                  brightness: brightness,
                  onTap: () => Navigator.of(sheetContext).pop(item.value),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      );
    },
  );
}

class _MenuRow<T> extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.brightness,
    required this.onTap,
  });

  final AppMenuItem<T> item;
  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        item.danger ? AppColors.brandRed : AppColors.onSurface(brightness);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenH,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(item.icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(color: color, fontSize: 14),
              ),
            ),
            if (item.trailing != null)
              Text(
                item.trailing!,
                style: TextStyle(
                  color:
                      item.trailingColor ?? AppColors.onSurfaceSubtle(brightness),
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
