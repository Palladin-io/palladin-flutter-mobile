import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../core/widgets/sheet_drag_handle.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/export/export_models.dart';
import '../cubit/export_cubit.dart';

/// Bottom sheet that exports a vault to a plaintext CSV/JSON file.
///
/// Flow: pick a format → read the plaintext-secrets warning → confirm →
/// the [ExportCubit] reveals + serializes + shares. Resolves to `true`
/// when the export reached the share sheet.
class ExportSheet extends StatelessWidget {
  const ExportSheet({
    super.key,
    required this.vaultId,
    required this.vaultName,
    this.wrappedVK,
  });

  final String vaultId;
  final String vaultName;
  final String? wrappedVK;

  static Future<bool?> show(
    BuildContext context, {
    required String vaultId,
    required String vaultName,
    String? wrappedVK,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => ExportSheet(
        vaultId: vaultId,
        vaultName: vaultName,
        wrappedVK: wrappedVK,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ExportCubit>(
      create: (_) => getIt<ExportCubit>(),
      child: _ExportSheetView(
        vaultId: vaultId,
        vaultName: vaultName,
        wrappedVK: wrappedVK,
      ),
    );
  }
}

class _ExportSheetView extends StatefulWidget {
  const _ExportSheetView({
    required this.vaultId,
    required this.vaultName,
    this.wrappedVK,
  });

  final String vaultId;
  final String vaultName;
  final String? wrappedVK;

  @override
  State<_ExportSheetView> createState() => _ExportSheetViewState();
}

class _ExportSheetViewState extends State<_ExportSheetView> {
  ExportFormat _format = ExportFormat.csv;

  Rect? _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _confirm() async {
    final auth = context.read<AuthBloc>().state;
    final l10n = AppLocalizations.of(context)!;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      _snack(l10n.exportErrorCrypto);
      return;
    }
    final origin = _shareOrigin();
    final keyCopy = Uint8List.fromList(auth.privateKey!);
    try {
      await context.read<ExportCubit>().export(
            vaultId: widget.vaultId,
            vaultName: widget.vaultName,
            format: _format,
            privateKey: keyCopy,
            wrappedVK: widget.wrappedVK,
            sharePositionOrigin: origin,
          );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocListener<ExportCubit, ExportState>(
      listener: (context, state) {
        if (state is ExportSuccess) {
          Navigator.of(context).pop(true);
          _snack(l10n.exportSuccess(state.entryCount));
        } else if (state is ExportFailure) {
          _snack(_errorMessage(l10n, state.reason));
        }
      },
      child: BlocBuilder<ExportCubit, ExportState>(
        builder: (context, state) {
          final busy = state is ExportInProgress;
          return Container(
            decoration: BoxDecoration(
              color: AppColors.modalBackground(brightness),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: SheetDragHandle()),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      AppSpacing.sm,
                      AppSpacing.screenH,
                      AppSpacing.section,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.exportTitle,
                          style: TextStyle(
                            color: AppColors.onSurface(brightness),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.section),
                        _FormatOption(
                          label: l10n.exportFormatCsv,
                          hint: l10n.exportCsvHint,
                          selected: _format == ExportFormat.csv,
                          onTap: busy
                              ? null
                              : () => setState(() => _format = ExportFormat.csv),
                        ),
                        const SizedBox(height: AppSpacing.cardGap),
                        _FormatOption(
                          label: l10n.exportFormatJson,
                          hint: l10n.exportJsonHint,
                          selected: _format == ExportFormat.json,
                          onTap: busy
                              ? null
                              : () =>
                                  setState(() => _format = ExportFormat.json),
                        ),
                        const SizedBox(height: AppSpacing.section),
                        WarningZone(
                          title: l10n.exportWarningTitle,
                          message: l10n.exportWarningBody,
                        ),
                      ],
                    ),
                  ),
                  SheetActionButtons(
                    onCancel: busy ? null : () => Navigator.of(context).pop(false),
                    onConfirm: busy ? null : _confirm,
                    confirmLabel: l10n.exportConfirm,
                    confirmColor: AppColors.brandRed,
                    busy: busy,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _errorMessage(AppLocalizations l10n, ExportFailureReason reason) =>
      switch (reason) {
        ExportFailureReason.empty => l10n.exportEmpty,
        ExportFailureReason.crypto => l10n.exportErrorCrypto,
        ExportFailureReason.network => l10n.exportErrorNetwork,
        ExportFailureReason.unknown => l10n.exportErrorUnknown,
      };
}

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? AppColors.brandRed.withValues(alpha: 0.08)
              : AppColors.cardFill(brightness),
          border: Border.all(
            color: selected
                ? AppColors.brandRed
                : AppColors.cardBorder(brightness),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? AppColors.brandRed
                  : AppColors.onSurfaceSubtle(brightness),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    hint,
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted(brightness),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
