import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/totp_config.dart';
import 'entry_form_widgets.dart';
import 'totp_setup_sheet.dart';

/// Editable list of user-defined custom fields (blob schema v2).
///
/// Owns the per-row [TextEditingController]s and reorder state. Reports the
/// current field list plus a validity flag on every change so the host
/// form can gate its Save button. Unknown-type fields (reserved / future
/// types the UI can't render) are held aside and re-appended on emit so an
/// older client editing a newer entry never drops them (spec §1
/// forward-compat).
class CustomFieldsEditor extends StatefulWidget {
  const CustomFieldsEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final List<CustomField> initial;

  /// Called with the current editable fields (complete ones only, plus any
  /// preserved unknown fields) and whether the editor has no invalid rows.
  final void Function(List<CustomField> fields, bool valid) onChanged;

  @override
  State<CustomFieldsEditor> createState() => _CustomFieldsEditorState();
}

class _CustomFieldsEditorState extends State<CustomFieldsEditor> {
  final List<_FieldDraft> _drafts = [];

  /// Unknown-type fields kept verbatim for round-trip; never rendered.
  final List<CustomField> _preserved = [];

  @override
  void initState() {
    super.initState();
    for (final field in widget.initial) {
      if (field.type == CustomFieldType.unknown) {
        _preserved.add(field);
      } else {
        _drafts.add(_FieldDraft.fromField(field));
      }
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final fields = <CustomField>[];
    for (final draft in _drafts) {
      final field = draft.toField();
      if (field != null) fields.add(field);
    }
    fields.addAll(_preserved);
    final valid = _drafts.every((d) => !d.hasContent || d.isComplete);
    widget.onChanged(fields, valid);
  }

  void _addField() {
    setState(() => _drafts.add(_FieldDraft.empty()));
    _emit();
  }

  void _removeField(_FieldDraft draft) {
    setState(() {
      _drafts.remove(draft);
      draft.dispose();
    });
    _emit();
  }

  Future<void> _changeType(_FieldDraft draft, CustomFieldType next) async {
    if (next == draft.type) return;
    if (next == CustomFieldType.totp) {
      final config = await TotpSetupSheet.show(context, initial: draft.totp);
      if (!mounted || config == null) return;
      setState(() {
        draft.type = next;
        draft.totp = config;
      });
    } else {
      setState(() {
        draft.type = next;
        draft.totp = null;
      });
    }
    _emit();
  }

  Future<void> _configureTotp(_FieldDraft draft) async {
    final config = await TotpSetupSheet.show(context, initial: draft.totp);
    if (!mounted || config == null) return;
    setState(() => draft.totp = config);
    _emit();
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final draft = _drafts.removeAt(oldIndex);
      _drafts.insert(newIndex, draft);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.entryCustomFieldsLabel,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (_drafts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.innerGap),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _drafts.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final draft = _drafts[index];
              return _FieldCard(
                key: ValueKey(draft.id),
                index: index,
                draft: draft,
                l10n: l10n,
                brightness: brightness,
                onChanged: _emit,
                onTypeChanged: (type) => _changeType(draft, type),
                onConfigureTotp: () => _configureTotp(draft),
                onRemove: () => _removeField(draft),
              );
            },
          ),
        ],
        const SizedBox(height: AppSpacing.innerGap),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addField,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.entryAddFieldAction),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandRed,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One editable custom field row: name + type + value (or TOTP status).
class _FieldCard extends StatelessWidget {
  const _FieldCard({
    super.key,
    required this.index,
    required this.draft,
    required this.l10n,
    required this.brightness,
    required this.onChanged,
    required this.onTypeChanged,
    required this.onConfigureTotp,
    required this.onRemove,
  });

  final int index;
  final _FieldDraft draft;
  final AppLocalizations l10n;
  final Brightness brightness;
  final VoidCallback onChanged;
  final ValueChanged<CustomFieldType> onTypeChanged;
  final VoidCallback onConfigureTotp;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final showNameError = draft.hasContent &&
        draft.labelController.text.trim().isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Tooltip(
                    message: l10n.entryFieldReorder,
                    child: Icon(
                      Icons.drag_indicator,
                      size: 18,
                      color: AppColors.onSurfaceSubtle(brightness),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: OnboardingTextField(
                  hintText: l10n.entryFieldNameHint,
                  controller: draft.labelController,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => onChanged(),
                  borderColor: showNameError ? AppColors.brandRed : null,
                  focusBorderColor:
                      showNameError ? AppColors.brandRed : null,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.onSurfaceSubtle(brightness),
                tooltip: l10n.entryFieldRemove,
                onPressed: onRemove,
              ),
            ],
          ),
          if (showNameError)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                l10n.entryFieldNameRequired,
                style: const TextStyle(
                  color: AppColors.brandRed,
                  fontSize: 11,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.innerGap),
          AppDropdownField<CustomFieldType>(
            label: l10n.entryFieldTypeLabel,
            value: draft.type,
            filled: false,
            onChanged: (type) {
              if (type != null) onTypeChanged(type);
            },
            items: [
              DropdownMenuItem(
                value: CustomFieldType.text,
                child: Text(l10n.entryFieldTypeText),
              ),
              DropdownMenuItem(
                value: CustomFieldType.concealed,
                child: Text(l10n.entryFieldTypeConcealed),
              ),
              DropdownMenuItem(
                value: CustomFieldType.totp,
                child: Text(l10n.entryFieldTypeTotp),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.innerGap),
          if (draft.type == CustomFieldType.totp)
            _TotpFieldStatus(
              configured: draft.totp != null,
              l10n: l10n,
              brightness: brightness,
              onConfigure: onConfigureTotp,
            )
          else
            OnboardingTextField(
              label: l10n.entryFieldValueLabel,
              controller: draft.valueController,
              obscureText: draft.type == CustomFieldType.concealed &&
                  draft.obscured,
              onChanged: (_) => onChanged(),
              suffixIcon: draft.type == CustomFieldType.concealed
                  ? EntryObscureToggle(
                      obscured: draft.obscured,
                      onPressed: () {
                        draft.obscured = !draft.obscured;
                        onChanged();
                      },
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

class _TotpFieldStatus extends StatelessWidget {
  const _TotpFieldStatus({
    required this.configured,
    required this.l10n,
    required this.brightness,
    required this.onConfigure,
  });

  final bool configured;
  final AppLocalizations l10n;
  final Brightness brightness;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          configured ? Icons.check_circle_outline : Icons.timer_outlined,
          size: 16,
          color: configured
              ? AppColors.positiveAccent
              : AppColors.onSurfaceSubtle(brightness),
        ),
        const SizedBox(width: AppSpacing.innerGap),
        Expanded(
          child: Text(
            configured ? l10n.totpConfigured : l10n.totpSetupTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 12,
            ),
          ),
        ),
        TextButton(
          onPressed: onConfigure,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.brandRed,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
          child: Text(
            configured ? l10n.totpReplaceSecret : l10n.totpScanQr,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Mutable editing state for one custom field.
class _FieldDraft {
  _FieldDraft({
    required this.id,
    required this.type,
    String label = '',
    String value = '',
    this.totp,
  })  : labelController = TextEditingController(text: label),
        valueController = TextEditingController(text: value);

  factory _FieldDraft.empty() =>
      _FieldDraft(id: CustomField.newId(), type: CustomFieldType.text);

  factory _FieldDraft.fromField(CustomField field) => _FieldDraft(
        id: field.id,
        type: field.type,
        label: field.label,
        value: field.type == CustomFieldType.totp ? '' : field.textValue,
        totp: field.totp,
      );

  final String id;
  CustomFieldType type;
  final TextEditingController labelController;
  final TextEditingController valueController;
  TotpConfig? totp;
  bool obscured = true;

  /// True when the row carries any user input worth validating.
  bool get hasContent =>
      labelController.text.trim().isNotEmpty ||
      valueController.text.trim().isNotEmpty ||
      totp != null;

  /// True when the row can be saved: a name, and a secret for TOTP.
  bool get isComplete {
    if (labelController.text.trim().isEmpty) return false;
    if (type == CustomFieldType.totp) return totp != null;
    return true;
  }

  CustomField? toField() {
    if (!isComplete) return null;
    final label = labelController.text.trim();
    return switch (type) {
      CustomFieldType.text => CustomField.text(
          id: id,
          label: label,
          value: valueController.text.trim(),
        ),
      CustomFieldType.concealed => CustomField.concealed(
          id: id,
          label: label,
          value: valueController.text.trim(),
        ),
      CustomFieldType.totp => CustomField.totpField(
          id: id,
          label: label,
          config: totp!,
        ),
      CustomFieldType.unknown => null,
    };
  }

  void dispose() {
    labelController.dispose();
    valueController.dispose();
  }
}
