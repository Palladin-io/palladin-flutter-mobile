import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/vault_entity.dart';
import 'vault_color_picker.dart';
import 'vault_icon_picker.dart';
import 'vault_visuals.dart';

/// Editable vault metadata bundle owned by [VaultForm].
///
/// `icon` carries a Material-icon name (`shield`, `folder`, …) — the
/// same identifier used by the web panel and the create-vault picker.
/// `color` is a `#RRGGBB` accent hex.
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

  VaultFormData copyWith({
    String? name,
    String? description,
    String? icon,
    String? color,
    GrantMode? grantMode,
  }) {
    return VaultFormData(
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      grantMode: grantMode ?? this.grantMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VaultFormData &&
      other.name == name &&
      other.description == description &&
      other.icon == icon &&
      other.color == color &&
      other.grantMode == grantMode;

  @override
  int get hashCode => Object.hash(name, description, icon, color, grantMode);
}

/// Reusable form for vault create / edit screens.
///
/// Mirrors the Astro mobile prototype — vault name, description, an
/// icon row, and a color row. Grant mode is intentionally not exposed
/// in the UI: new vaults default to [GrantMode.granular] and existing
/// values are passed through unchanged.
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
    final accent = VaultVisuals.colorFor(_selectedColor);

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
        VaultIconPicker(
          selected: _selectedIcon,
          accentColor: accent,
          onSelected: (icon) {
            setState(() => _selectedIcon = icon);
            _emit();
          },
        ),
        const SizedBox(height: 20),
        _SectionLabel(text: l10n.vaultColorLabel),
        const SizedBox(height: 8),
        VaultColorPicker(
          selected: _selectedColor,
          onSelected: (color) {
            setState(() => _selectedColor = color);
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
        color: AppColors.textSecondaryMobile,
      ),
    );
  }
}
