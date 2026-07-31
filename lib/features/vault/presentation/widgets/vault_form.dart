import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/icon_color_browser_sheet.dart';
import '../../../../core/widgets/icon_picker_grid.dart' show IconMoreTile;
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/vault_entity.dart';
import 'vault_icon_picker.dart';
import 'vault_visuals.dart';

/// Editable vault metadata bundle owned by [VaultForm].
///
/// `icon` carries a Material-icon name (`shield`, `folder`, …) or a URL
/// (custom uploaded icon). `color` is a `#RRGGBB` accent hex.
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
/// Mirrors the Astro mobile prototype — vault name, description and a
/// single icon row. Color is no longer surfaced as its own swatch row;
/// it is chosen inside the icon-browser sheet (opened via the trailing
/// "..." tile in the icon row), matching the agents approve sheet UX.
/// Grant mode is intentionally not exposed in the UI: new vaults default
/// to [GrantMode.granular] and existing values are passed through
/// unchanged.
///
/// Pass [onPickCustomIcon] to enable the "Upload custom icon" affordance
/// below the icon picker. Omit it (null) in create flows where there is
/// no vault ID available yet — the affordance is hidden automatically.
class VaultForm extends StatefulWidget {
  const VaultForm({
    super.key,
    required this.initial,
    required this.onChanged,
    this.onPickCustomIcon,
  });

  final VaultFormData initial;
  final ValueChanged<VaultFormData> onChanged;

  /// Optional callback invoked when the user taps the upload-icon button.
  /// Should return the final icon value to display — either a `file://`
  /// local path (create flow, upload deferred) or an `https://` public URL
  /// (settings flow, upload immediate) — or `null` on cancellation. When
  /// non-null an upload button is shown in the icon row. VaultForm updates
  /// its own icon state with the returned value so the upload circle shows
  /// a preview immediately.
  final Future<String?> Function()? onPickCustomIcon;

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
    _descriptionController = TextEditingController(
      text: widget.initial.description,
    )..addListener(_emit);
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
    widget.onChanged(
      VaultFormData(
        name: _nameController.text,
        description: _descriptionController.text,
        icon: _selectedIcon,
        color: _selectedColor,
        grantMode: _selectedMode,
      ),
    );
  }

  /// Opens the full icon + color browser sheet. Mirrors the agents
  /// approve sheet flow — `...` tile reveals every available glyph and
  /// the six-color swatch row in one place.
  Future<void> _openVaultBrowser() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await IconColorBrowserSheet.show(
      context,
      icons: VaultVisuals.iconChoices
          .map(
            (c) => (name: c.name, icon: c.icon, paletteColor: c.paletteColor),
          )
          .toList(),
      colorOptions: VaultVisuals.colorChoices
          .map(VaultVisuals.colorFor)
          .toList(),
      initialIconKey: _selectedIcon,
      initialColor: VaultVisuals.colorFor(_selectedColor),
      title: l10n.agentIconBrowserTitle,
      confirmLabel: l10n.agentIconChoose,
      onPickCustom: widget.onPickCustomIcon,
    );
    if (!mounted || result == null) return;
    final pickedColor = result.color;
    final matchedHex = VaultVisuals.colorChoices.firstWhere(
      (hex) => VaultVisuals.colorFor(hex).toARGB32() == pickedColor.toARGB32(),
      orElse: () => VaultVisuals.defaultColorHex,
    );
    setState(() {
      if (result.iconKey != null) _selectedIcon = result.iconKey!;
      _selectedColor = matchedHex;
    });
    _emit();
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
        const SizedBox(height: AppSpacing.fieldGap),
        OnboardingTextField(
          label: l10n.vaultDescriptionLabel,
          controller: _descriptionController,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        _SectionLabel(text: l10n.vaultIconLabel),
        const SizedBox(height: AppSpacing.innerGap),
        VaultIconPicker(
          selected: _selectedIcon,
          accentColor: accent,
          onSelected: (icon) {
            setState(() => _selectedIcon = icon);
            _emit();
          },
          moreTile: IconMoreTile(onTap: _openVaultBrowser),
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
