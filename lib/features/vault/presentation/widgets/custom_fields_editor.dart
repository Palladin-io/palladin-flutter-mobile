import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_menu_sheet.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/custom_field.dart';
import 'entry_form_widgets.dart';

/// Editable grouped list of non-TOTP custom fields (text / multiline /
/// hidden) — the "Additional fields" section (blob schema v2).
///
/// TOTP fields are owned by the dedicated 2FA section, not here. Each row
/// is one line: a type glyph, an inline label + value, and a "⋯" menu that
/// opens a bottom sheet for changing type, toggling agent visibility
/// (text/multiline only), reordering, and removing. Unknown-type fields
/// are preserved verbatim for round-trip (spec §1).
class CustomFieldsEditor extends StatefulWidget {
  const CustomFieldsEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final List<CustomField> initial;

  /// Emits the current editable fields (complete ones + preserved unknown
  /// fields) and whether every row is valid.
  final void Function(List<CustomField> fields, bool valid) onChanged;

  @override
  State<CustomFieldsEditor> createState() => _CustomFieldsEditorState();
}

class _CustomFieldsEditorState extends State<CustomFieldsEditor> {
  final List<_FieldDraft> _drafts = [];
  final List<CustomField> _preserved = [];

  @override
  void initState() {
    super.initState();
    for (final field in widget.initial) {
      switch (field.type) {
        case CustomFieldType.text:
        case CustomFieldType.multiline:
        case CustomFieldType.concealed:
          _drafts.add(_FieldDraft.fromField(field));
        case CustomFieldType.totp:
        case CustomFieldType.unknown:
          // totp lives in the 2FA section; unknown types round-trip as-is.
          _preserved.add(field);
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

  Future<void> _addField() async {
    final type = await showAppMenuSheet<CustomFieldType>(
      context: context,
      title: AppLocalizations.of(context)!.entryAddFieldAction,
      items: [
        _typeItem(CustomFieldType.text),
        _typeItem(CustomFieldType.multiline),
        _typeItem(CustomFieldType.concealed),
      ],
    );
    if (type == null || !mounted) return;
    setState(() => _drafts.add(_FieldDraft.empty(type)));
    _emit();
  }

  AppMenuItem<CustomFieldType> _typeItem(CustomFieldType type) {
    final l10n = AppLocalizations.of(context)!;
    return AppMenuItem(
      value: type,
      icon: customFieldTypeIcon(type),
      label: _typeLabel(l10n, type),
      trailing: _typeHint(l10n, type),
    );
  }

  Future<void> _openRowMenu(_FieldDraft draft) async {
    final l10n = AppLocalizations.of(context)!;
    final index = _drafts.indexOf(draft);
    final canAgent = draft.type.canBeAgentVisible;
    final action = await showAppMenuSheet<_RowAction>(
      context: context,
      items: [
        AppMenuItem(
          value: _RowAction.typeText,
          icon: customFieldTypeIcon(CustomFieldType.text),
          label: _typeLabel(l10n, CustomFieldType.text),
          trailing: draft.type == CustomFieldType.text ? '✓' : null,
          trailingColor: AppColors.brandRed,
        ),
        AppMenuItem(
          value: _RowAction.typeMultiline,
          icon: customFieldTypeIcon(CustomFieldType.multiline),
          label: _typeLabel(l10n, CustomFieldType.multiline),
          trailing: draft.type == CustomFieldType.multiline ? '✓' : null,
          trailingColor: AppColors.brandRed,
        ),
        AppMenuItem(
          value: _RowAction.typeHidden,
          icon: customFieldTypeIcon(CustomFieldType.concealed),
          label: _typeLabel(l10n, CustomFieldType.concealed),
          trailing: draft.type == CustomFieldType.concealed ? '✓' : null,
          trailingColor: AppColors.brandRed,
        ),
        if (canAgent)
          AppMenuItem(
            value: _RowAction.toggleAgent,
            icon: Icons.smart_toy_outlined,
            label: l10n.entryFieldAgentVisible,
            trailing: draft.agentVisible
                ? l10n.entryFieldOn
                : l10n.entryFieldOff,
            trailingColor: draft.agentVisible ? AppColors.vaultBlue : null,
            dividerBefore: true,
          ),
        AppMenuItem(
          value: _RowAction.moveUp,
          icon: Icons.arrow_upward,
          label: l10n.entryFieldMoveUp,
          dividerBefore: true,
        ),
        AppMenuItem(
          value: _RowAction.moveDown,
          icon: Icons.arrow_downward,
          label: l10n.entryFieldMoveDown,
        ),
        AppMenuItem(
          value: _RowAction.remove,
          icon: Icons.delete_outline,
          label: l10n.entryFieldRemove,
          danger: true,
          dividerBefore: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    setState(() {
      switch (action) {
        case _RowAction.typeText:
          draft.setType(CustomFieldType.text);
        case _RowAction.typeMultiline:
          draft.setType(CustomFieldType.multiline);
        case _RowAction.typeHidden:
          draft.setType(CustomFieldType.concealed);
        case _RowAction.toggleAgent:
          draft.agentVisible = !draft.agentVisible;
        case _RowAction.moveUp:
          if (index > 0) {
            _drafts
              ..removeAt(index)
              ..insert(index - 1, draft);
          }
        case _RowAction.moveDown:
          if (index < _drafts.length - 1) {
            _drafts
              ..removeAt(index)
              ..insert(index + 1, draft);
          }
        case _RowAction.remove:
          _drafts.remove(draft);
          draft.dispose();
      }
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final hairline = AppColors.onSurface(brightness).withValues(alpha: 0.08);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EntrySectionHeader(label: l10n.entryCustomFieldsLabel),
        const SizedBox(height: AppSpacing.innerGap),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.cardBorder(brightness),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _drafts.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: hairline),
                _FieldRow(
                  key: ValueKey(_drafts[i].id),
                  draft: _drafts[i],
                  brightness: brightness,
                  l10n: l10n,
                  onChanged: _emit,
                  onMenu: () => _openRowMenu(_drafts[i]),
                ),
              ],
              if (_drafts.isNotEmpty)
                Divider(height: 1, thickness: 1, color: hairline),
              _AddRow(label: l10n.entryAddFieldAction, onTap: _addField),
            ],
          ),
        ),
      ],
    );
  }

  static String _typeLabel(AppLocalizations l10n, CustomFieldType type) =>
      switch (type) {
        CustomFieldType.text => l10n.entryFieldTypeText,
        CustomFieldType.multiline => l10n.entryFieldTypeMultiline,
        CustomFieldType.concealed => l10n.entryFieldTypeConcealed,
        CustomFieldType.totp => l10n.entryFieldTypeTotp,
        CustomFieldType.unknown => l10n.entryFieldTypeText,
      };

  static String? _typeHint(AppLocalizations l10n, CustomFieldType type) =>
      switch (type) {
        CustomFieldType.text => l10n.entryFieldTypeTextHint,
        CustomFieldType.multiline => l10n.entryFieldTypeMultilineHint,
        CustomFieldType.concealed => l10n.entryFieldTypeConcealedHint,
        _ => null,
      };
}

enum _RowAction {
  typeText,
  typeMultiline,
  typeHidden,
  toggleAgent,
  moveUp,
  moveDown,
  remove,
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.draft,
    required this.brightness,
    required this.l10n,
    required this.onChanged,
    required this.onMenu,
  });

  final _FieldDraft draft;
  final Brightness brightness;
  final AppLocalizations l10n;
  final VoidCallback onChanged;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final showLabelError =
        draft.hasContent && draft.labelController.text.trim().isEmpty;
    final isMultiline = draft.type == CustomFieldType.multiline;
    final isHidden = draft.type == CustomFieldType.concealed;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TypeGlyph(type: draft.type, brightness: brightness),
          const SizedBox(width: AppSpacing.innerGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: draft.labelController,
                  onChanged: (_) => onChanged(),
                  maxLength: CustomField.maxAgentFieldLabel,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 12,
                  ),
                  decoration: InputDecoration.collapsed(
                    hintText: l10n.entryFieldNameLabel,
                    hintStyle: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 12,
                    ),
                  ).copyWith(counterText: ''),
                ),
                if (showLabelError)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      l10n.entryFieldNameRequired,
                      style: const TextStyle(
                        color: AppColors.brandRed,
                        fontSize: 11,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xxs),
                TextField(
                  controller: draft.valueController,
                  onChanged: (_) => onChanged(),
                  obscureText: isHidden && draft.obscured,
                  minLines: isMultiline ? 2 : 1,
                  maxLines: isMultiline ? null : 1,
                  keyboardType: isMultiline ? TextInputType.multiline : null,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 13,
                    fontFamily: isMultiline ? 'monospace' : null,
                  ),
                  decoration: InputDecoration.collapsed(
                    hintText: l10n.entryFieldValueLabel,
                    hintStyle: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.innerGap),
          if (draft.agentVisible && draft.type.canBeAgentVisible)
            Padding(
              padding: const EdgeInsets.only(
                right: AppSpacing.xs,
                top: AppSpacing.xs,
              ),
              child: Tooltip(
                message: l10n.entryFieldAgentVisibleTip,
                child: const Icon(
                  Icons.smart_toy_outlined,
                  size: 14,
                  color: AppColors.vaultBlue,
                ),
              ),
            ),
          if (isHidden)
            _RowIconButton(
              icon: draft.obscured ? Icons.visibility : Icons.visibility_off,
              tooltip: l10n.vaultRevealValue,
              brightness: brightness,
              onPressed: () {
                draft.obscured = !draft.obscured;
                onChanged();
              },
            ),
          _RowIconButton(
            icon: Icons.more_vert,
            tooltip: l10n.entryFieldMenu,
            brightness: brightness,
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}

class _TypeGlyph extends StatelessWidget {
  const _TypeGlyph({required this.type, required this.brightness});

  final CustomFieldType type;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      margin: const EdgeInsets.only(top: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.onSurface(brightness).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Icon(
        customFieldTypeIcon(type),
        size: 12,
        color: AppColors.onSurfaceSubtle(brightness),
      ),
    );
  }
}

class _RowIconButton extends StatelessWidget {
  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.brightness,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Brightness brightness;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Icon(
            icon,
            size: 16,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              Icons.add,
              size: 16,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
            const SizedBox(width: AppSpacing.innerGap),
            Text(
              label,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mutable editing state for one non-TOTP custom field.
class _FieldDraft {
  _FieldDraft({
    required this.id,
    required this.type,
    String label = '',
    String value = '',
    this.agentVisible = false,
  }) : labelController = TextEditingController(text: label),
       valueController = TextEditingController(text: value);

  factory _FieldDraft.empty(CustomFieldType type) =>
      _FieldDraft(id: CustomField.newId(), type: type);

  factory _FieldDraft.fromField(CustomField field) => _FieldDraft(
    id: field.id,
    type: field.type,
    label: field.label,
    value: field.textValue,
    agentVisible: field.agentVisible,
  );

  final String id;
  CustomFieldType type;
  final TextEditingController labelController;
  final TextEditingController valueController;
  bool agentVisible;
  bool obscured = true;

  void setType(CustomFieldType next) {
    type = next;
    // Agent visibility only applies to text/multiline — drop it otherwise.
    if (!next.canBeAgentVisible) agentVisible = false;
  }

  bool get hasContent =>
      labelController.text.trim().isNotEmpty ||
      valueController.text.trim().isNotEmpty;

  bool get isComplete => labelController.text.trim().isNotEmpty;

  CustomField? toField() {
    if (!isComplete) return null;
    final label = labelController.text.trim();
    final value = valueController.text.trim();
    return switch (type) {
      CustomFieldType.text => CustomField.text(
        id: id,
        label: label,
        value: value,
        agentVisible: agentVisible,
      ),
      CustomFieldType.multiline => CustomField.multiline(
        id: id,
        label: label,
        value: value,
        agentVisible: agentVisible,
      ),
      CustomFieldType.concealed => CustomField.concealed(
        id: id,
        label: label,
        value: value,
      ),
      CustomFieldType.totp || CustomFieldType.unknown => null,
    };
  }

  void dispose() {
    labelController.dispose();
    valueController.dispose();
  }
}
