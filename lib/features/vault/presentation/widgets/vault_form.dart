import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/vault_entity.dart';

/// Editable vault metadata bundle owned by [VaultForm].
class VaultFormData {
  const VaultFormData({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.grantMode,
  });

  final String name;
  final String description;
  final String icon;
  final String color;
  final GrantMode grantMode;
}

/// Predefined emoji set for the vault icon picker.
///
/// Single source of truth — keep in sync with the web prototype so
/// the same icons render across platforms.
const List<String> kVaultIconChoices = <String>[
  '🔒', '🔑', '🗝️', '🏦', '📁',
  '💼', '🛡️', '⚙️', '🔐', '🌐',
];

/// Predefined `#RRGGBB` color choices for the vault color picker.
///
/// Picked to match the prototype palette and be visually distinct on
/// the dark surface.
const List<String> kVaultColorChoices = <String>[
  '#48ECDF', // teal
  '#FF4F4F', // brand red
  '#F4B942', // amber
  '#2EC4B6', // mint
  '#A78BFA', // violet
  '#60A5FA', // sky
  '#F472B6', // pink
  '#FFAB87', // peach
];

/// Reusable form for vault create / edit screens.
///
/// Owns its own controllers + form state and surfaces every change via
/// [onChanged]. Stateless from the parent's perspective — pass an
/// [initial] bundle and read updates through the callback. The parent
/// decides when to enable the submit button and what action to take.
class VaultForm extends StatefulWidget {
  const VaultForm({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final VaultFormData initial;
  final ValueChanged<VaultFormData> onChanged;

  @override
  State<VaultForm> createState() => _VaultFormState();
}

class _VaultFormState extends State<VaultForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _selectedIcon;
  late String _selectedColor;
  late GrantMode _selectedMode;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial.name)
      ..addListener(_emit);
    _descriptionController =
        TextEditingController(text: widget.initial.description)
          ..addListener(_emit);
    _selectedIcon = widget.initial.icon;
    _selectedColor = widget.initial.color;
    _selectedMode = widget.initial.grantMode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(VaultFormData(
      name: _nameController.text,
      description: _descriptionController.text,
      icon: _selectedIcon,
      color: _selectedColor,
      grantMode: _selectedMode,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingTextField(
          label: l10n.vaultNameLabel,
          controller: _nameController,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        OnboardingTextField(
          label: l10n.vaultDescriptionLabel,
          controller: _descriptionController,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 20),
        _SectionLabel(text: l10n.vaultIconLabel),
        const SizedBox(height: 8),
        _IconPicker(
          icons: kVaultIconChoices,
          selected: _selectedIcon,
          onSelected: (icon) {
            setState(() => _selectedIcon = icon);
            _emit();
          },
        ),
        const SizedBox(height: 20),
        _SectionLabel(text: l10n.vaultColorLabel),
        const SizedBox(height: 8),
        _ColorPicker(
          colors: kVaultColorChoices,
          selected: _selectedColor,
          onSelected: (color) {
            setState(() => _selectedColor = color);
            _emit();
          },
        ),
        const SizedBox(height: 20),
        _SectionLabel(text: l10n.vaultModeLabel),
        const SizedBox(height: 8),
        _ModeSelector(
          selected: _selectedMode,
          onChanged: (mode) {
            setState(() => _selectedMode = mode);
            _emit();
          },
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({
    required this.icons,
    required this.selected,
    required this.onSelected,
  });

  final List<String> icons;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final icon in icons)
          GestureDetector(
            onTap: () => onSelected(icon),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: icon == selected
                      ? AppColors.tealAccent
                      : AppColors.buttonBorder,
                  width: icon == selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                icon,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final List<String> colors;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final hex in colors)
          GestureDetector(
            onTap: () => onSelected(hex),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _parseHex(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hex == selected
                      ? AppColors.textPrimary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Color _parseHex(String hex) {
    final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
    final value = int.tryParse(cleaned, radix: 16) ?? 0xFFFFFF;
    return Color(0xFF000000 | value);
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.selected, required this.onChanged});

  final GrantMode selected;
  final ValueChanged<GrantMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: _ModeChoice(
            label: l10n.vaultModeFull,
            description: l10n.vaultModeFullDescription,
            selected: selected == GrantMode.full,
            color: AppColors.tealAccent,
            onTap: () => onChanged(GrantMode.full),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ModeChoice(
            label: l10n.vaultModeGranular,
            description: l10n.vaultModeGranularDescription,
            selected: selected == GrantMode.granular,
            color: AppColors.strengthFair,
            onTap: () => onChanged(GrantMode.granular),
          ),
        ),
      ],
    );
  }
}

class _ModeChoice extends StatelessWidget {
  const _ModeChoice({
    required this.label,
    required this.description,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.15)
              : AppColors.darkSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : AppColors.buttonBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? color : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
