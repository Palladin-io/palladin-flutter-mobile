import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
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
    _nameController =
        TextEditingController(text: widget.initialName?.trim() ?? '');
    _typeController = TextEditingController();
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
    Navigator.of(context).pop<ApproveAgentResult>((
      name: name.isEmpty ? null : name,
      type: typeText.isEmpty ? null : typeText,
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
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                _FieldLabel(label: l10n.agentTypeLabel),
                const SizedBox(height: 8),
                _AgentTypeAutocomplete(
                  controller: _typeController,
                  onChanged: (value, _) {
                    setState(() => _selectedTypeValue = value);
                  },
                ),
                const SizedBox(height: 16),
                _FieldLabel(label: l10n.agentIconLabel),
                const SizedBox(height: 8),
                _IconGrid(
                  selected: _selectedIcon,
                  selectedColor: _selectedColor,
                  onSelected: (value) =>
                      setState(() => _selectedIcon = value),
                  onMoreTapped: _openIconBrowser,
                ),
                const SizedBox(height: 12),
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

  Future<void> _openIconBrowser() async {
    final result = await _AgentIconBrowserSheet.show(
      context,
      initialIcon: _selectedIcon,
      initialColor: _selectedColor,
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
  State<_AgentTypeAutocomplete> createState() =>
      _AgentTypeAutocompleteState();
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

  List<({String value, String label})> _filteredOptions(
    AppLocalizations l10n,
  ) {
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
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
                      horizontal: 14,
                      vertical: 10,
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
    final isFromBrowser = selected != null && !presets.contains(selected);
    // When a browser-picked icon is active, inject it at the end of the
    // preset list (replacing the last slot) so the grid still has
    // exactly the same pool size and "more" stays last.
    final effectivePresets = isFromBrowser
        ? [...presets.sublist(0, presets.length - 1), selected!]
        : presets;

    return IconPickerGrid(
      itemCount: effectivePresets.length,
      itemBuilder: (i) {
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
// Icon browser modal — full icon set + color picker
// ────────────────────────────────────────────────────────────────────────

typedef _IconBrowserResult = ({String iconKey, Color color});

/// Full icon browser modal — surfaces every icon in [agentIconAll] and a
/// six-color picker. Mirrors the web panel's `AgentIconBrowser`.
class _AgentIconBrowserSheet extends StatefulWidget {
  const _AgentIconBrowserSheet({
    required this.initialIcon,
    required this.initialColor,
  });

  final String? initialIcon;
  final Color initialColor;

  static Future<_IconBrowserResult?> show(
    BuildContext context, {
    String? initialIcon,
    required Color initialColor,
  }) {
    return showModalBottomSheet<_IconBrowserResult>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgentIconBrowserSheet(
        initialIcon: initialIcon,
        initialColor: initialColor,
      ),
    );
  }

  @override
  State<_AgentIconBrowserSheet> createState() =>
      _AgentIconBrowserSheetState();
}

class _AgentIconBrowserSheetState extends State<_AgentIconBrowserSheet> {
  late String? _localIcon = widget.initialIcon;
  late Color _localColor = widget.initialColor;

  void _confirm() {
    final icon = _localIcon;
    if (icon == null) return;
    Navigator.of(context).pop<_IconBrowserResult>((
      iconKey: icon,
      color: _localColor,
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.agentIconBrowserTitle,
                        style: TextStyle(
                          color: AppColors.onSurface(brightness),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: AppColors.onSurfaceSubtle(brightness),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _BrowserIconGrid(
                  selectedIcon: _localIcon,
                  selectedColor: _localColor,
                  onSelected: (icon) => setState(() => _localIcon = icon),
                ),
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.cardBorder(brightness),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.agentIconColorLabel,
                  style: TextStyle(
                    color: AppColors.onSurfaceMuted(brightness),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                _ColorPickerRow(
                  selected: _localColor,
                  onSelected: (color) => setState(() => _localColor = color),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                AppColors.onSurface(brightness),
                            side: BorderSide(
                              color: AppColors.cardBorder(brightness),
                            ),
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
                        label: l10n.agentIconChoose,
                        icon: Icons.check,
                        onPressed: _localIcon == null ? null : _confirm,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 8-column grid of every icon in [agentIconAll]. Selected tile uses the
/// user-picked accent color.
class _BrowserIconGrid extends StatelessWidget {
  const _BrowserIconGrid({
    required this.selectedIcon,
    required this.selectedColor,
    required this.onSelected,
  });

  final String? selectedIcon;
  final Color selectedColor;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: agentIconAll.length,
      itemBuilder: (_, index) {
        final iconKey = agentIconAll[index];
        final selected = iconKey == selectedIcon;
        final accent = agentIconColor(iconKey);
        return InkWell(
          onTap: () => onSelected(iconKey),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? selectedColor.withValues(alpha: 0.18)
                  : accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? selectedColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(
              agentIconData(iconKey),
              size: 20,
              color: selected ? selectedColor : accent,
            ),
          ),
        );
      },
    );
  }
}

/// Row of six color swatches — single-select. The active swatch gets a
/// cream / navy ring (brightness-aware) so it reads against any color.
class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow({
    required this.selected,
    required this.onSelected,
  });

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final ringColor = AppColors.onSurface(brightness);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final color in agentColorOptions)
          GestureDetector(
            onTap: () => onSelected(color),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected.toARGB32() == color.toARGB32()
                      ? ringColor
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
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
