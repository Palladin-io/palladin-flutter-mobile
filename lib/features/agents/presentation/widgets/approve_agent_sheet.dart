import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import 'agent_format.dart';

/// Values an admin sets when approving a pending agent.
///
/// All fields are optional — a `null` field tells the API to keep its
/// server-side default.
typedef ApproveAgentResult = ({
  String? name,
  String? type,
  String? iconKey,
});

/// Approve-agent form shown as a bottom sheet before a pending agent is
/// granted access.
///
/// Mirrors the web panel's `ApproveAgentDialog`: title + subtitle, name
/// input, type chips (13 built-in types), icon grid (15 presets) and a
/// 1:2 footer with a subtle Cancel and a green tinted Approve button.
///
/// Resolves to an [ApproveAgentResult] when the admin confirms, or
/// `null` when they cancel / dismiss without confirming.
class ApproveAgentSheet extends StatefulWidget {
  const ApproveAgentSheet({super.key, this.initialName});

  /// Pre-fills the name input — pass the agent's existing display name
  /// so re-opening the sheet does not lose the prior input.
  final String? initialName;

  /// Opens the sheet and returns the admin's choices, or `null` on
  /// cancel / dismiss.
  static Future<ApproveAgentResult?> show(
    BuildContext context, {
    String? initialName,
  }) {
    return showModalBottomSheet<ApproveAgentResult>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ApproveAgentSheet(initialName: initialName),
    );
  }

  @override
  State<ApproveAgentSheet> createState() => _ApproveAgentSheetState();
}

class _ApproveAgentSheetState extends State<ApproveAgentSheet> {
  late final TextEditingController _nameController;

  /// Selected agent type wire value, or `null` when none chosen.
  String? _selectedType;

  /// Selected Material icon name, or `null` when none chosen.
  String? _selectedIcon;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.initialName?.trim() ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _nameController.text.trim();
    Navigator.of(context).pop<ApproveAgentResult>((
      name: name.isEmpty ? null : name,
      type: _selectedType,
      iconKey: _selectedIcon,
    ));
  }

  void _cancel() {
    Navigator.of(context).pop<ApproveAgentResult?>(null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 16),
                Text(
                  l10n.agentApproveTitle,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.agentApproveSetupHint,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                OnboardingTextField(
                  controller: _nameController,
                  label: l10n.agentNameLabel,
                  hintText: l10n.agentNamePlaceholder,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _confirm(),
                ),
                const SizedBox(height: 16),
                _FieldLabel(label: l10n.agentTypeLabel),
                const SizedBox(height: 8),
                _TypeChips(
                  selected: _selectedType,
                  onSelected: (value) =>
                      setState(() => _selectedType = value),
                ),
                const SizedBox(height: 16),
                _FieldLabel(label: l10n.agentIconLabel),
                const SizedBox(height: 8),
                _IconGrid(
                  selected: _selectedIcon,
                  onSelected: (value) =>
                      setState(() => _selectedIcon = value),
                ),
                const SizedBox(height: 20),
                _ApproveFooter(
                  onCancel: _cancel,
                  onConfirm: _confirm,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small section label matching the [OnboardingTextField] label style so
/// the type and icon groups align with the name input above them.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurfaceMuted(brightness),
      ),
    );
  }
}

/// The thirteen agent-type choice chips. Tapping a selected chip again
/// deselects it so "no type" stays reachable.
class _TypeChips extends StatelessWidget {
  const _TypeChips({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = agentTypeOptions(l10n);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _ChoiceChipTile(
            label: option.label,
            isSelected: selected == option.value,
            onTap: () => onSelected(
              selected == option.value ? null : option.value,
            ),
          ),
      ],
    );
  }
}

/// A single bordered, tappable type chip. Selected state uses the green
/// approve accent ([AppColors.positiveAccent]) so the approve flow reads
/// consistently from chip → CTA. Unselected uses the subtle card border.
class _ChoiceChipTile extends StatelessWidget {
  const _ChoiceChipTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final borderColor = isSelected
        ? AppColors.positiveAccent
        : AppColors.cardBorder(brightness);
    final textColor = isSelected
        ? AppColors.positiveAccent
        : AppColors.onSurfaceMuted(brightness);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.positiveAccent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wrap of preset icon squares. Tapping a selected icon again deselects
/// it. Mirrors the web icon grid layout (5 per row at the default 40 px
/// tile size — wraps naturally on narrower screens).
class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final iconKey in agentIconOptions)
          _IconTile(
            iconKey: iconKey,
            isSelected: selected == iconKey,
            onTap: () => onSelected(selected == iconKey ? null : iconKey),
          ),
      ],
    );
  }
}

/// A single 40×40 tappable icon square in the [_IconGrid].
///
/// Unselected: tinted with the glyph's preset accent ([agentIconColor]).
/// Selected: green ring + green-tinted fill matching the approve CTA.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.iconKey,
    required this.isSelected,
    required this.onTap,
  });

  final String iconKey;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = agentIconColor(iconKey);
    final fill = isSelected
        ? AppColors.positiveAccent.withValues(alpha: 0.18)
        : accent.withValues(alpha: 0.12);
    final iconColor = isSelected ? AppColors.positiveAccent : accent;
    final borderColor =
        isSelected ? AppColors.positiveAccent : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Icon(agentIconData(iconKey), size: 20, color: iconColor),
        ),
      ),
    );
  }
}

/// Footer row matching the web modal pattern: a subtle Cancel (1 unit
/// wide) next to a green tinted Approve CTA (2 units wide).
class _ApproveFooter extends StatelessWidget {
  const _ApproveFooter({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Row(
      children: [
        Expanded(
          flex: 1,
          child: SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.onSurface(brightness),
                side: BorderSide(color: AppColors.cardBorder(brightness)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                l10n.apiKeysCancel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ApproveActionButton(
            label: l10n.agentsApprove,
            onPressed: onConfirm,
          ),
        ),
      ],
    );
  }
}

/// Reusable green-tinted "approve" CTA. Mirrors the web button style:
/// green text + icon on a translucent green fill with a green border.
///
/// Exported so the action zone and inline card button can render the
/// same affordance — no duplicated styling.
class ApproveActionButton extends StatelessWidget {
  const ApproveActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.check_circle_outline,
    this.isLoading = false,
    this.height = 44,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool isLoading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: TextButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.positiveAccent,
                ),
              )
            : Icon(icon, size: 16, color: AppColors.positiveAccent),
        label: Text(
          label,
          style: const TextStyle(
            color: AppColors.positiveAccent,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.positiveAccent,
          disabledForegroundColor:
              AppColors.positiveAccent.withValues(alpha: 0.4),
          backgroundColor: AppColors.positiveAccent.withValues(alpha: 0.12),
          disabledBackgroundColor:
              AppColors.positiveAccent.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: AppColors.positiveAccent.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
