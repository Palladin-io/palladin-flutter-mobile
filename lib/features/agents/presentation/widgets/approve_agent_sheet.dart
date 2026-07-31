import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/approve_action_button.dart';
import '../../../../core/widgets/icon_color_browser_sheet.dart';
import '../../../../core/widgets/icon_picker_grid.dart'
    show IconPickerGrid, IconMoreTile, IconPresetTile;
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import 'agent_format.dart';

/// Values an admin sets when approving a pending agent.
///
/// All fields are optional — a `null` field tells the API to keep its
/// server-side default. The selected icon color is currently a UI-only
/// affordance (mirrors the web preset highlight) and is not persisted.
typedef ApproveAgentResult = ({
  String? name,
  String? type,
  String? iconKey,
  String? iconColor,
});

/// Approve-agent form shown as a bottom sheet before a pending agent is
/// granted access.
///
/// Mirrors the web panel's `ApproveAgentDialog`: title + subtitle, name
/// input, agent-type autocomplete combobox (built-in suggestions + free
/// form), icon picker (15 presets + "more" tile that opens a browser
/// with the full glyph catalogue plus a six-color picker) and a 1:2
/// footer with a subtle Cancel and a green tinted Approve button.
///
/// Resolves to an [ApproveAgentResult] when the admin confirms, or
/// `null` when they cancel / dismiss without confirming.
class ApproveAgentSheet extends StatefulWidget {
  const ApproveAgentSheet({super.key, this.initialName, this.initialType});

  /// Pre-fills the name input — pass the agent's existing display name
  /// so re-opening the sheet does not lose the prior input.
  final String? initialName;

  /// Pre-fills the type input — pass the type the agent reported during
  /// enrollment (`X-Agent-Type`) so the operator confirms it rather than
  /// re-typing it from scratch.
  final String? initialType;

  /// Opens the sheet and returns the admin's choices, or `null` on
  /// cancel / dismiss.
  static Future<ApproveAgentResult?> show(
    BuildContext context, {
    String? initialName,
    String? initialType,
  }) {
    return showModalBottomSheet<ApproveAgentResult>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ApproveAgentSheet(initialName: initialName, initialType: initialType),
    );
  }

  @override
  State<ApproveAgentSheet> createState() => _ApproveAgentSheetState();
}

class _ApproveAgentSheetState extends State<ApproveAgentSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _typeController;

  /// Resolved wire value for the selected type. Stays in sync with
  /// [_typeController]: when the user picks a built-in option it stores
  /// the camelCase wire value; when they type freely it stores the raw
  /// text (mirrors the web combobox semantics).
  String? _selectedTypeValue;

  /// Selected Material icon name, or `null` when none chosen.
  String? _selectedIcon;

  /// Selected accent color for the icon picker — purely UI-only today
  /// (the mobile API does not yet round-trip an iconColor field).
  Color _selectedColor = defaultAgentColor;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialName?.trim() ?? '',
    );
    final type = widget.initialType?.trim() ?? '';
    _typeController = TextEditingController(text: type);
    // Seed the wire value directly — setting the controller text before the
    // autocomplete mounts does not fire its onChanged listener.
    _selectedTypeValue = type.isEmpty ? null : type;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _nameController.text.trim();
    final typeText = _selectedTypeValue?.trim() ?? '';
    // file:// paths are local — agent icon upload requires the agent ID which
    // doesn't exist until after approval. Send null for now; upload is future work.
    final iconForApi = (_selectedIcon?.startsWith('file://') ?? false)
        ? null
        : _selectedIcon;
    Navigator.of(context).pop<ApproveAgentResult>((
      name: name.isEmpty ? null : name,
      type: typeText.isEmpty ? null : typeText,
      iconKey: iconForApi,
      iconColor: agentColorHex(_selectedColor),
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
          bottom:
              MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.fieldGap,
              AppSpacing.screenH,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHandle(),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.agentApproveTitle,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.chipGap),
                Text(
                  l10n.agentApproveSetupHint,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                OnboardingTextField(
                  controller: _nameController,
                  label: l10n.agentNameLabel,
                  hintText: l10n.agentNamePlaceholder,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.lg),
                _FieldLabel(label: l10n.agentTypeLabel),
                const SizedBox(height: AppSpacing.sm),
                _AgentTypeAutocomplete(
                  controller: _typeController,
                  onChanged: (value, _) {
                    setState(() => _selectedTypeValue = value);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                _FieldLabel(label: l10n.agentIconLabel),
                const SizedBox(height: AppSpacing.sm),
                _IconGrid(
                  selected: _selectedIcon,
                  selectedColor: _selectedColor,
                  onSelected: (value) => setState(() => _selectedIcon = value),
                  onMoreTapped: _openIconBrowser,
                ),
                const SizedBox(height: AppSpacing.xl),
                _ApproveFooter(onCancel: _cancel, onConfirm: _confirm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openIconBrowser() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await IconColorBrowserSheet.show(
      context,
      icons: agentIconAll
          .map(
            (name) => (
              name: name,
              icon: agentIconData(name),
              paletteColor: agentIconColor(name),
            ),
          )
          .toList(),
      colorOptions: agentColorOptions,
      initialIconKey: _selectedIcon,
      initialColor: _selectedColor,
      title: l10n.agentIconBrowserTitle,
      confirmLabel: l10n.agentIconChoose,
      onPickCustom: () async {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 85,
        );
        if (file == null) return null;
        return 'file://${file.path}';
      },
    );
    if (!mounted || result == null) return;
    setState(() {
      _selectedIcon = result.iconKey;
      _selectedColor = result.color;
    });
  }
}

// ────────────────────────────────────────────────────────────────────────
// Field label — small caps muted label used above the type/icon groups
// ────────────────────────────────────────────────────────────────────────

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

// ────────────────────────────────────────────────────────────────────────
// Agent type autocomplete combobox
// ────────────────────────────────────────────────────────────────────────

/// Free-form text input that surfaces a filtered list of built-in agent
/// types as a dropdown overlay. Mirrors the web panel's
/// `AgentTypeCombobox`:
///
/// * Typing filters the suggestions (case-insensitive substring match
///   on the localized label).
/// * Tapping a suggestion fills the field with the localized label and
///   stores the camelCase wire value for the parent.
/// * The user may also keep the freely-typed text as a custom type —
///   the wire value falls back to whatever they typed.
///
/// Selection is communicated to the parent via [onChanged]
/// `(wireValue, label)` so the sheet can preserve the canonical wire
/// value for the API call while showing the friendly label in the
/// input.
class _AgentTypeAutocomplete extends StatefulWidget {
  const _AgentTypeAutocomplete({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;

  /// Fired whenever the wire value changes — either because the user
  /// picked a suggestion (wireValue = preset value, label = localized
  /// label) or typed free text (wireValue = label = raw text).
  final void Function(String wireValue, String label) onChanged;

  @override
  State<_AgentTypeAutocomplete> createState() => _AgentTypeAutocompleteState();
}

class _AgentTypeAutocompleteState extends State<_AgentTypeAutocomplete> {
  final LayerLink _link = LayerLink();
  final FocusNode _focus = FocusNode();
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_handleFocusChange);
    widget.controller.addListener(_handleTextChange);
  }

  @override
  void dispose() {
    _hideOverlay();
    _focus
      ..removeListener(_handleFocusChange)
      ..dispose();
    widget.controller.removeListener(_handleTextChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focus.hasFocus) {
      _showOverlay();
    } else {
      // Defer hide so a tap on a suggestion is still registered.
      Future<void>.delayed(const Duration(milliseconds: 120), _hideOverlay);
    }
  }

  void _handleTextChange() {
    widget.onChanged(widget.controller.text, widget.controller.text);
    if (_focus.hasFocus) {
      _refreshOverlay();
    }
  }

  void _showOverlay() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_overlay!);
  }

  void _refreshOverlay() => _overlay?.markNeedsBuild();

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _selectOption({required String wireValue, required String label}) {
    widget.controller
      ..text = label
      ..selection = TextSelection.collapsed(offset: label.length);
    widget.onChanged(wireValue, label);
    _focus.unfocus();
    _hideOverlay();
  }

  List<({String value, String label})> _filteredOptions(AppLocalizations l10n) {
    final query = widget.controller.text.trim().toLowerCase();
    final options = agentTypeOptions(l10n);
    if (query.isEmpty) return options;
    return options
        .where((opt) => opt.label.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final l10n = AppLocalizations.of(context)!;

    return CompositedTransformTarget(
      link: _link,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.inputFill(brightness),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.inputBorder(brightness)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.fieldGap),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                style: TextStyle(
                  color: AppColors.inputText(brightness),
                  fontSize: 14,
                ),
                cursorColor: AppColors.inputText(brightness),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  isCollapsed: true,
                  hintText: l10n.agentTypePlaceholder,
                  hintStyle: TextStyle(
                    color: AppColors.inputHint(brightness),
                    fontSize: 14,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.cardPadding,
                  ),
                ),
                textInputAction: TextInputAction.next,
              ),
            ),
            Icon(
              Icons.expand_more,
              size: 18,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final brightness = Theme.of(context).brightness;
    final l10n = AppLocalizations.of(context)!;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) {
      return const SizedBox.shrink();
    }
    final size = renderBox.size;
    final filtered = _filteredOptions(l10n);
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Positioned(
      width: size.width,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        offset: Offset(0, size.height + 4),
        child: Material(
          elevation: 0,
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: AppColors.modalBackground(brightness),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder(brightness)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.dropdownShadow(brightness),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (_, index) {
                final option = filtered[index];
                return InkWell(
                  onTap: () => _selectOption(
                    wireValue: option.value,
                    label: option.label,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.cardPadding,
                      vertical: AppSpacing.cardGap,
                    ),
                    child: Text(
                      option.label,
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Icon grid (presets + "more" tile)
// ────────────────────────────────────────────────────────────────────────

/// Two-row responsive grid of preset icon squares with a trailing "more"
/// tile that opens the full icon browser.
///
/// When an icon from the browser is active it replaces the last preset
/// slot so the "more" tile always stays at the end of the second row.
class _IconGrid extends StatelessWidget {
  const _IconGrid({
    required this.selected,
    required this.selectedColor,
    required this.onSelected,
    required this.onMoreTapped,
  });

  final String? selected;
  final Color selectedColor;
  final ValueChanged<String?> onSelected;
  final VoidCallback onMoreTapped;

  @override
  Widget build(BuildContext context) {
    final presets = agentIconOptions;
    // file:// paths (custom images picked via the browser) are never
    // injected into the preset grid — the icon grid just shows "none selected"
    // while the custom image is stored internally.
    final isCustomUrl =
        selected != null &&
        (selected!.startsWith('file://') ||
            selected!.startsWith('https://') ||
            selected!.startsWith('http://'));
    final isFromBrowser =
        !isCustomUrl && selected != null && !presets.contains(selected);
    // When a browser-picked icon is active, inject it at the end of the
    // preset list (replacing the last slot) so the grid still has
    // exactly the same pool size and "more" stays last.
    final effectivePresets = isFromBrowser
        ? [...presets.sublist(0, presets.length - 1), selected!]
        : presets;

    return IconPickerGrid(
      itemCount: effectivePresets.length,
      itemBuilder: (i, _) {
        final iconKey = effectivePresets[i];
        return IconPresetTile(
          icon: agentIconData(iconKey),
          paletteColor: agentIconColor(iconKey),
          isSelected: selected == iconKey,
          selectedColor: selectedColor,
          onTap: () => onSelected(selected == iconKey ? null : iconKey),
        );
      },
      moreTile: IconMoreTile(onTap: onMoreTapped),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Footer + sheet handle
// ────────────────────────────────────────────────────────────────────────

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
        const SizedBox(width: AppSpacing.cardGap),
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
