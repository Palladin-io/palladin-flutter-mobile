import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'sheet_action_buttons.dart';
import 'sheet_drag_handle.dart';

/// Shared confirmation layout; owners supply copy and retain mutation handling.
class ConfirmationSheet extends StatelessWidget {
  const ConfirmationSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
  });
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Material(
      color: AppColors.modalBackground(brightness),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: SheetDragHandle()),
                  const SizedBox(height: AppSpacing.section),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface(brightness),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.innerGap),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.onSurfaceMuted(brightness),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SheetActionButtons(
            onCancel: () => Navigator.of(context).pop(false),
            onConfirm: () => Navigator.of(context).pop(true),
            confirmLabel: confirmLabel,
            cancelLabel: cancelLabel,
            confirmColor: AppColors.primaryAction,
            equalActions: true,
          ),
        ],
      ),
    );
  }
}
