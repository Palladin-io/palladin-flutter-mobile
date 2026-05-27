import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/agent.dart';
import '../bloc/agents_cubit.dart';
import 'agent_format.dart';

/// Inline editable form for an agent — shown inside the details card on
/// the agent detail screen. Mirrors the web panel's `AgentEditForm`.
///
/// Fields are always visible. Interactivity is gated by [canEdit] (true
/// only when the operator has the agent-manage permission AND the agent
/// is active). The Save button is hidden when [canEdit] is false and
/// disabled when the form is not dirty / valid.
class AgentEditForm extends StatefulWidget {
  const AgentEditForm({
    super.key,
    required this.agent,
    required this.canEdit,
  });

  final Agent agent;

  /// When false all fields render as disabled and the Save button is
  /// hidden — matches the web panel's read-only mode for non-active
  /// agents and viewers without manage permission.
  final bool canEdit;

  @override
  State<AgentEditForm> createState() => _AgentEditFormState();
}

class _AgentEditFormState extends State<AgentEditForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  String? _type;
  String? _lastAgentId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.agent.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.agent.description ?? '');
    _type = widget.agent.type;
    _lastAgentId = widget.agent.agentId;
  }

  @override
  void didUpdateWidget(AgentEditForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset the controllers only when the underlying agent changes —
    // mirrors the web form's `useEffect(..., [agent.agentId])`. Resetting
    // on every rebuild would wipe the operator's in-flight edits.
    if (widget.agent.agentId != _lastAgentId) {
      _nameController.text = widget.agent.name ?? '';
      _descriptionController.text = widget.agent.description ?? '';
      _type = widget.agent.type;
      _lastAgentId = widget.agent.agentId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final trimmedName = _nameController.text.trim();
    final trimmedDesc = _descriptionController.text.trim();
    return trimmedName != (widget.agent.name?.trim() ?? '') ||
        trimmedDesc != (widget.agent.description?.trim() ?? '') ||
        (_type ?? '') != (widget.agent.type ?? '');
  }

  bool _canSubmit({required bool isSaving}) {
    if (!widget.canEdit || isSaving) return false;
    final trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) return false;
    return _isDirty;
  }

  Future<void> _onSave() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<AgentsCubit>();
    await cubit.updateAgent(
      widget.agent.agentId,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
    );
    if (!mounted) return;
    if (cubit.state.mutationError == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.agentsEditSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocBuilder<AgentsCubit, AgentsState>(
      buildWhen: (prev, curr) =>
          prev.mutatingAgentId != curr.mutatingAgentId ||
          prev.agents != curr.agents,
      builder: (context, state) {
        final isSaving = state.mutatingAgentId == widget.agent.agentId;
        final enabled = widget.canEdit && !isSaving;
        // Rebuild the canSubmit check on each field change to drive the
        // Save button's enabled state.
        return AnimatedBuilder(
          animation: Listenable.merge(
              [_nameController, _descriptionController]),
          builder: (context, _) {
            final canSubmit = _canSubmit(isSaving: isSaving);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OnboardingTextField(
                  controller: _nameController,
                  label: l10n.agentsEditName,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _TypeDropdown(
                  value: _type,
                  enabled: enabled,
                  onChanged: (next) => setState(() => _type = next),
                ),
                const SizedBox(height: 12),
                OnboardingTextField(
                  controller: _descriptionController,
                  label: l10n.agentsEditDescription,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                ),
                if (widget.canEdit) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _SaveButton(
                      isSaving: isSaving,
                      onPressed: canSubmit ? _onSave : null,
                    ),
                  ),
                ],
                // When the form is read-only we surface a one-line hint so
                // the operator understands why the inputs are greyed out.
                if (!widget.canEdit && widget.agent.isPending) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.agentsApproveHint,
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// Type dropdown — mirrors the web `<select>` rendering. Lists the 13
/// built-in agent types from [agentTypeOptions]; when the agent already
/// carries a custom type that is not in the list, that value is appended
/// so it survives a round-trip through the form.
class _TypeDropdown extends StatelessWidget {
  const _TypeDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final options = agentTypeOptions(l10n);
    final builtInValues = options.map((o) => o.value).toSet();

    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Text(
          l10n.agentTypeLabel,
          style: TextStyle(
            color: AppColors.inputHint(brightness),
            fontSize: 14,
          ),
        ),
      ),
      for (final option in options)
        DropdownMenuItem<String?>(
          value: option.value,
          child: Text(
            option.label,
            style: TextStyle(
              color: AppColors.inputText(brightness),
              fontSize: 14,
            ),
          ),
        ),
      if (value != null && !builtInValues.contains(value))
        DropdownMenuItem<String?>(
          value: value,
          child: Text(
            value!,
            style: TextStyle(
              color: AppColors.inputText(brightness),
              fontSize: 14,
            ),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.agentTypeLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceMuted(brightness),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.inputFill(brightness),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.inputBorder(brightness)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: value,
              dropdownColor: AppColors.modalBackground(brightness),
              icon: Icon(
                Icons.keyboard_arrow_down,
                color: AppColors.onSurfaceSubtle(brightness),
              ),
              style: TextStyle(
                color: AppColors.inputText(brightness),
                fontSize: 14,
              ),
              onChanged: enabled ? onChanged : null,
              items: items,
            ),
          ),
        ),
      ],
    );
  }
}

/// Brand-red filled "Save" pill. Mirrors the web `Button variant="accent"`
/// — the primary save action on the inline form.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.isSaving, required this.onPressed});

  final bool isSaving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 36,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandRed,
          disabledBackgroundColor: AppColors.brandRed.withValues(alpha: 0.3),
          foregroundColor: AppColors.onBrandRed,
          disabledForegroundColor:
              AppColors.onBrandRed.withValues(alpha: 0.5),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: isSaving
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.onBrandRed,
                ),
              )
            : Text(l10n.agentsEditSave),
      ),
    );
  }
}
