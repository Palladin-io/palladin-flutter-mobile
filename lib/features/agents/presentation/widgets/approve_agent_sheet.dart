import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
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
/// Lets the admin optionally set a display name, pick an agent type
/// (Open Claw / Claude Code / Hermes / Other) and choose an icon.
///
/// Resolves to an [ApproveAgentResult] when the admin confirms, or
/// `null` when they cancel / dismiss without confirming.
class ApproveAgentSheet extends StatefulWidget {
  const ApproveAgentSheet({super.key});

  /// Opens the sheet and returns the admin's choices, or `null` on
  /// cancel / dismiss.
  static Future<ApproveAgentResult?> show(BuildContext context) {
    return showModalBottomSheet<ApproveAgentResult>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ApproveAgentSheet(),
    );
  }

  @override
  State<ApproveAgentSheet> createState() => _ApproveAgentSheetState();
}

class _ApproveAgentSheetState extends State<ApproveAgentSheet> {
  final TextEditingController _nameController = TextEditingController();

  /// Selected agent type wire value, or `null` when none chosen.
  String? _selectedType;

  /// Selected Material icon name, or `null` when none chosen.
  String? _selectedIcon;

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
                const SizedBox(height: 20),
                Text(
                  l10n.agentApproveTitle,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                OnboardingTextField(
                  controller: _nameController,
                  label: l10n.agentNameLabel,
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
                const SizedBox(height: 24),
                PrimaryButton(
                  label: l10n.agentsApprove,
                  onPressed: _confirm,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pop<ApproveAgentResult?>(null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.onSurface(brightness),
                    side: BorderSide(color: AppColors.onSurface(brightness)),
                    minimumSize: const Size(double.infinity, 44),
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

/// The four agent-type choice chips. Tapping a selected chip again
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

/// A single bordered, tappable type chip. Selected state uses the brand
/// red border + tint; unselected uses the subtle card border.
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
        ? AppColors.brandRed
        : AppColors.cardBorder(brightness);
    final textColor = isSelected
        ? AppColors.brandRed
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
                ? AppColors.brandRed.withValues(alpha: 0.12)
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

/// 4×2 grid of preset icon squares. Tapping a selected icon again
/// deselects it.
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
    final brightness = Theme.of(context).brightness;
    final borderColor = isSelected
        ? AppColors.brandRed
        : AppColors.cardBorder(brightness);
    final iconColor = isSelected
        ? AppColors.brandRed
        : AppColors.onSurfaceMuted(brightness);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.brandRed.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Icon(agentIconData(iconKey), size: 20, color: iconColor),
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
