import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../../../grants/presentation/grant_method_label.dart';

/// Compact multi-select for grant methods (CVT-148/149) — the mobile counterpart of the web methods
/// dropdown. A single 44px field (matching the app's inputs) shows the chosen methods as a summary
/// and opens a picker with one checkable row + description per method (so the modal stays small and
/// scales as methods are added). The `get` warning lives inside the picker.
class GrantMethodsSelector extends StatelessWidget {
  const GrantMethodsSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.requested = const [],
    this.enabled = true,
  });

  final List<GrantMethod> value;
  final List<GrantMethod> requested;
  final bool enabled;
  final ValueChanged<List<GrantMethod>> onChanged;

  static String _label(AppLocalizations l10n, GrantMethod m) => grantMethodLabel(l10n, m);

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<List<GrantMethod>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MethodsPickerSheet(initial: value, requested: requested),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final summary = GrantMethod.values
        .where(value.contains)
        .map((m) => _label(l10n, m))
        .join(', ');

    return InkWell(
      onTap: enabled ? () => _openPicker(context) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardBorder(brightness)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                summary.isEmpty ? l10n.approvalMethodsSelect : summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: summary.isEmpty
                      ? AppColors.onSurfaceMuted(brightness)
                      : AppColors.onSurface(brightness),
                  fontSize: 13,
                ),
              ),
            ),
            Icon(
              Icons.expand_more,
              size: 18,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet picker: one checkable row + description per method (mirrors the web dropdown's
/// option list), plus the amber `get` warning. Returns the chosen list on "Done".
class _MethodsPickerSheet extends StatefulWidget {
  const _MethodsPickerSheet({required this.initial, required this.requested});

  final List<GrantMethod> initial;
  final List<GrantMethod> requested;

  @override
  State<_MethodsPickerSheet> createState() => _MethodsPickerSheetState();
}

class _MethodsPickerSheetState extends State<_MethodsPickerSheet> {
  late final List<GrantMethod> _selected = List.of(widget.initial);

  void _toggle(GrantMethod m) {
    setState(() {
      if (_selected.contains(m)) {
        _selected.remove(m);
      } else {
        _selected.add(m);
      }
    });
  }

  String _label(AppLocalizations l10n, GrantMethod m) =>
      GrantMethodsSelector._label(l10n, m);

  String _desc(AppLocalizations l10n, GrantMethod m) => switch (m) {
    GrantMethod.get => l10n.approvalMethodGetDesc,
    GrantMethod.exec => l10n.approvalMethodExecDesc,
    GrantMethod.inject => l10n.approvalMethodInjectDesc,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder(brightness),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.approvalMethodsLegend,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                for (final m in GrantMethod.values)
                  _MethodRow(
                    label: _label(l10n, m),
                    description: _desc(l10n, m),
                    selected: _selected.contains(m),
                    requested: widget.requested.contains(m),
                    requestedLabel: l10n.approvalMethodRequested,
                    brightness: brightness,
                    onTap: () => _toggle(m),
                  ),
                // AnimatedSize grows/collapses the sheet smoothly as the `get`
                // warning appears, instead of snapping to the new height.
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _selected.contains(GrantMethod.get)
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: WarningZone(
                            title: l10n.approvalMethodWarningZone,
                            message: l10n.approvalMethodGetWarning,
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
          // Shared gray footer band — same convention as every other sheet.
          SheetActionButtons(
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected),
            confirmLabel: l10n.approvalMethodsDone,
            confirmColor: AppColors.positiveAccent,
          ),
        ],
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.label,
    required this.description,
    required this.selected,
    required this.requested,
    required this.requestedLabel,
    required this.brightness,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final bool requested;
  final String requestedLabel;
  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: selected
                  ? AppColors.positiveAccent
                  : AppColors.onSurfaceSubtle(brightness),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: AppColors.onSurface(brightness),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (requested) ...[
                        const SizedBox(width: 6),
                        Text(
                          requestedLabel,
                          style: TextStyle(
                            color: AppColors.onSurfaceSubtle(brightness),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted(brightness),
                      fontSize: 11,
                      height: 1.35,
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
