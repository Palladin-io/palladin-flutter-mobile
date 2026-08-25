import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_toggle.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/entry_entity.dart';

/// Value-free editor for CLI parameters declared by a Script. Only the
/// definitions enter Agent Discovery; values are supplied locally at runtime.
final class ScriptParametersEditor extends StatefulWidget {
  const ScriptParametersEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final List<ScriptParameterDefinition> initial;
  final ValueChanged<List<ScriptParameterDefinition>> onChanged;

  @override
  State<ScriptParametersEditor> createState() => _ScriptParametersEditorState();
}

final class _ScriptParametersEditorState extends State<ScriptParametersEditor> {
  final List<_ParameterDraft> _drafts = [];

  @override
  void initState() {
    super.initState();
    _drafts.addAll(widget.initial.map(_ParameterDraft.fromDefinition));
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged(
    _drafts.map((draft) => draft.definition).toList(growable: false),
  );

  void _add() {
    if (_drafts.length >= 32) return;
    setState(() => _drafts.add(_ParameterDraft()));
    _emit();
  }

  void _remove(_ParameterDraft draft) {
    setState(() => _drafts.remove(draft));
    draft.dispose();
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final draft in _drafts)
          Container(
            key: ValueKey(draft.id),
            margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            decoration: BoxDecoration(
              color: AppColors.cardFill(brightness),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder(brightness)),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: OnboardingTextField(
                        label: l10n.entryScriptParameterName,
                        hintText: l10n.entryScriptParameterNameHint,
                        controller: draft.name,
                        onChanged: (_) => _emit(),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _remove(draft),
                      tooltip: l10n.entryScriptParameterRemove,
                      icon: const Icon(Icons.close, size: 18),
                      color: AppColors.onSurfaceSubtle(brightness),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.innerGap),
                OnboardingTextField(
                  label: l10n.entryScriptParameterDescription,
                  controller: draft.description,
                  onChanged: (_) => _emit(),
                ),
                const SizedBox(height: AppSpacing.innerGap),
                AppDropdownField<ScriptParameterType>(
                  label: l10n.entryScriptParameterType,
                  value: draft.type,
                  filled: false,
                  items: [
                    for (final type in ScriptParameterType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(_typeLabel(l10n, type)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    draft.type = value;
                    _emit();
                  },
                ),
                const SizedBox(height: AppSpacing.innerGap),
                Row(
                  children: [
                    Expanded(child: Text(l10n.entryScriptParameterRequired)),
                    AppToggle(
                      value: draft.required,
                      onChanged: (value) {
                        setState(() => draft.required = value);
                        _emit();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _drafts.length < 32 ? _add : null,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.entryScriptParameterAdd),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandRed,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _typeLabel(AppLocalizations l10n, ScriptParameterType type) =>
      switch (type) {
        ScriptParameterType.string => l10n.entryScriptParameterTypeString,
        ScriptParameterType.integer => l10n.entryScriptParameterTypeInteger,
        ScriptParameterType.number => l10n.entryScriptParameterTypeNumber,
        ScriptParameterType.boolean => l10n.entryScriptParameterTypeBoolean,
      };
}

final class _ParameterDraft {
  _ParameterDraft({
    String name = '',
    String description = '',
    this.type = ScriptParameterType.string,
    this.required = true,
    this.minimum,
    this.maximum,
    this.minLength,
    this.maxLength,
    this.allowedValues = const [],
  }) : id = _nextId++,
       name = TextEditingController(text: name),
       description = TextEditingController(text: description);

  factory _ParameterDraft.fromDefinition(ScriptParameterDefinition value) =>
      _ParameterDraft(
        name: value.name,
        description: value.description,
        type: value.type,
        required: value.required,
        minimum: value.minimum,
        maximum: value.maximum,
        minLength: value.minLength,
        maxLength: value.maxLength,
        allowedValues: List<Object>.from(value.allowedValues),
      );

  static int _nextId = 0;
  final int id;
  final TextEditingController name;
  final TextEditingController description;
  ScriptParameterType type;
  bool required;
  final num? minimum;
  final num? maximum;
  final int? minLength;
  final int? maxLength;
  final List<Object> allowedValues;

  ScriptParameterDefinition get definition => ScriptParameterDefinition(
    name: name.text.trim(),
    description: description.text.trim(),
    type: type,
    required: required,
    minimum: minimum,
    maximum: maximum,
    minLength: minLength,
    maxLength: maxLength,
    allowedValues: List<Object>.from(allowedValues),
  );

  void dispose() {
    name.dispose();
    description.dispose();
  }
}
