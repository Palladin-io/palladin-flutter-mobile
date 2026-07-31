import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_autocomplete_field.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/entry_entity.dart';
import 'entry_field_names.dart';

/// Editor for a script's declared credential references (spec §5): each row
/// maps an environment-variable name to a field on another entry. v1 keeps
/// the mapping fully explicit — there is no in-body placeholder
/// substitution.
class ScriptRefsEditor extends StatefulWidget {
  const ScriptRefsEditor({
    super.key,
    required this.vaultId,
    required this.entries,
    required this.initial,
    required this.onChanged,
  });

  /// Vault the script (and its reference targets) live in — written onto
  /// each [ScriptRef] so the agent CLI can resolve it.
  final String vaultId;

  /// Candidate target entries (key / credential entries in the vault, minus
  /// the entry being edited).
  final List<EntryEntity> entries;

  final List<ScriptRef> initial;

  /// Emits the complete references (env + entry + field all set).
  final ValueChanged<List<ScriptRef>> onChanged;

  @override
  State<ScriptRefsEditor> createState() => _ScriptRefsEditorState();
}

class _ScriptRefsEditorState extends State<ScriptRefsEditor> {
  final List<_RefDraft> _drafts = [];

  @override
  void initState() {
    super.initState();
    for (final ref in widget.initial) {
      _drafts.add(
        _RefDraft(env: ref.env, entryId: ref.entryId, field: ref.field),
      );
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
    final refs = <ScriptRef>[
      for (final d in _drafts)
        if (d.env.trim().isNotEmpty && d.entryId != null && d.field != null)
          ScriptRef(
            env: d.env.trim(),
            vaultId: widget.vaultId,
            entryId: d.entryId!,
            field: d.field!,
          ),
    ];
    widget.onChanged(refs);
  }

  void _add() {
    setState(() => _drafts.add(_RefDraft()));
    _emit();
  }

  void _remove(_RefDraft draft) {
    setState(() {
      _drafts.remove(draft);
      draft.dispose();
    });
    _emit();
  }

  EntryEntity? _entryById(String? id) {
    if (id == null) return null;
    for (final e in widget.entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final draft in _drafts)
          _RefCard(
            key: ValueKey(draft.id),
            draft: draft,
            entries: widget.entries,
            selectedEntry: _entryById(draft.entryId),
            l10n: l10n,
            brightness: brightness,
            onChanged: _emit,
            onRemove: () => _remove(draft),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.entryAddRefAction),
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

class _RefCard extends StatelessWidget {
  const _RefCard({
    super.key,
    required this.draft,
    required this.entries,
    required this.selectedEntry,
    required this.l10n,
    required this.brightness,
    required this.onChanged,
    required this.onRemove,
  });

  final _RefDraft draft;
  final List<EntryEntity> entries;
  final EntryEntity? selectedEntry;
  final AppLocalizations l10n;
  final Brightness brightness;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final fieldOptions = selectedEntry == null
        ? const <WellKnownField>[]
        : wellKnownFieldsFor(selectedEntry!.type, l10n);
    // Keep the selected field valid for the chosen entry.
    final currentField = fieldOptions.any((f) => f.wire == draft.field)
        ? draft.field
        : null;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: OnboardingTextField(
                  label: l10n.entryRefEnvLabel,
                  hintText: l10n.entryRefEnvHint,
                  controller: draft.envController,
                  onChanged: (_) => onChanged(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.onSurfaceSubtle(brightness),
                tooltip: l10n.entryRefRemove,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.innerGap),
          AppAutocompleteField<EntryEntity>(
            label: l10n.entryRefEntryLabel,
            hintText: l10n.entryRefEntryHint,
            initialText: selectedEntry?.label ?? '',
            options: entries,
            displayString: (e) => e.label,
            onSelected: (entry) {
              draft.entryId = entry.id;
              final options = wellKnownFieldsFor(entry.type, l10n);
              if (!options.any((f) => f.wire == draft.field)) {
                draft.field = options.isNotEmpty ? options.first.wire : null;
              }
              onChanged();
            },
            onTextChanged: (text) {
              if (text.trim().isEmpty) {
                draft.entryId = null;
                draft.field = null;
                onChanged();
              }
            },
          ),
          const SizedBox(height: AppSpacing.innerGap),
          AppDropdownField<String>(
            label: l10n.entryRefFieldLabel,
            value: currentField,
            enabled: selectedEntry != null,
            filled: false,
            hint: Text(
              l10n.entryRefFieldLabel,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 13,
              ),
            ),
            onChanged: (value) {
              draft.field = value;
              onChanged();
            },
            items: [
              for (final option in fieldOptions)
                DropdownMenuItem(value: option.wire, child: Text(option.label)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RefDraft {
  _RefDraft({String env = '', this.entryId, this.field})
    : id = _nextId++,
      envController = TextEditingController(text: env);

  static int _nextId = 0;

  final int id;
  final TextEditingController envController;
  String? entryId;
  String? field;

  String get env => envController.text;

  void dispose() => envController.dispose();
}
