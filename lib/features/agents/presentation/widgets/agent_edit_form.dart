import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/icon_color_browser_sheet.dart';
import '../../../../core/widgets/icon_picker_grid.dart'
    show IconPickerGrid, IconMoreTile, IconPresetTile, ImagePresetTile;
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../data/datasources/agents_remote_data_source.dart';
import '../../data/services/agent_icon_upload_service.dart';
import '../../domain/entities/agent.dart';
import '../bloc/agents_cubit.dart';
import 'agent_format.dart';

/// Strips any query string from [url] — used so we send the canonical
/// (stable) public URL to the backend while keeping a `?v=` cache-busting
/// query around locally for the avatar.
String _stripQuery(String url) {
  final q = url.indexOf('?');
  return q < 0 ? url : url.substring(0, q);
}

/// Appends a cache-busting `?v={now}` query to [url] so a re-upload to the
/// same S3 key forces every [NetworkImage] in the tree to refetch.
String _withCacheBust(String url) =>
    '${_stripQuery(url)}?v=${DateTime.now().millisecondsSinceEpoch}';

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
  String? _iconKey;
  Color _iconColor = defaultAgentColor;
  String? _lastAgentId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.agent.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.agent.description ?? '');
    _type = widget.agent.type;
    _iconKey = widget.agent.iconKey;
    _iconColor =
        _parseHexColor(widget.agent.iconColor) ?? defaultAgentColor;
    _lastAgentId = widget.agent.agentId;
  }

  @override
  void didUpdateWidget(AgentEditForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset the form only when the underlying agent changes —
    // mirrors the web form's `useEffect(..., [agent.agentId])`. Resetting
    // on every rebuild would wipe the operator's in-flight edits.
    if (widget.agent.agentId != _lastAgentId) {
      _nameController.text = widget.agent.name ?? '';
      _descriptionController.text = widget.agent.description ?? '';
      _type = widget.agent.type;
      _iconKey = widget.agent.iconKey;
      _iconColor =
          _parseHexColor(widget.agent.iconColor) ?? defaultAgentColor;
      _lastAgentId = widget.agent.agentId;
    }
  }

  static Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(cleaned.length == 6 ? 0xFF000000 | value : value);
  }

  static String _colorToHex(Color color) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
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
    final savedColor =
        _parseHexColor(widget.agent.iconColor) ?? defaultAgentColor;
    return trimmedName != (widget.agent.name?.trim() ?? '') ||
        trimmedDesc != (widget.agent.description?.trim() ?? '') ||
        (_type ?? '') != (widget.agent.type ?? '') ||
        (_iconKey ?? '') != (widget.agent.iconKey ?? '') ||
        _iconColor.toARGB32() != savedColor.toARGB32();
  }

  bool _canSubmit({required bool isSaving}) {
    if (!widget.canEdit || isSaving) return false;
    final trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) return false;
    return _isDirty;
  }

  Future<void> _openIconBrowser() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await IconColorBrowserSheet.show(
      context,
      icons: agentIconAll
          .map((name) => (
                name: name,
                icon: agentIconData(name),
                paletteColor: agentIconColor(name),
              ))
          .toList(),
      colorOptions: agentColorOptions,
      initialIconKey: _iconKey,
      initialColor: _iconColor,
      title: l10n.agentIconBrowserTitle,
      confirmLabel: l10n.agentIconChoose,
      onPickCustom: () async {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 85,
        );
        if (picked == null || !mounted) return null;
        // Try to upload to S3 via presign. Falls back to a local file://
        // path when the backend endpoint isn't available yet — the browser
        // sheet still shows a preview, but the URL is stripped before
        // the PATCH so it won't reach the API.
        try {
          final service =
              AgentIconUploadService(getIt<AgentsRemoteDataSource>());
          final publicUrl = await service.uploadIcon(
            widget.agent.agentId,
            File(picked.path),
          );
          // S3 reuses the same key (`agent-icons/{agentId}/icon.{ext}`) on
          // every re-upload, so the public URL is byte-for-byte identical
          // across uploads. Evict any cached copy and append a
          // cache-busting `?v={now}` query so:
          //   1. `_isDirty` flips true (new string != old string) even if
          //      the canonical URL is unchanged → Save button enables.
          //   2. Every `NetworkImage` in the tree refetches fresh bytes
          //      instead of serving the stale cached image.
          PaintingBinding.instance.imageCache
              .evict(NetworkImage(publicUrl));
          return _withCacheBust(publicUrl);
        } on AgentIconUploadException catch (e) {
          if (!mounted) return null;
          final l10n = AppLocalizations.of(context)!;
          final msg = switch (e.kind) {
            AgentIconUploadErrorKind.fileTooLarge => l10n.vaultIconUploadSizeError,
            AgentIconUploadErrorKind.unsupportedFormat => l10n.vaultIconUploadFormatError,
            _ => l10n.vaultIconUploadError,
          };
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
          return null;
        } catch (_) {
          if (!mounted) return null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.vaultIconUploadError)),
          );
          return null;
        }
      },
    );
    if (!mounted || result == null) return;
    setState(() {
      _iconKey = result.iconKey;
      _iconColor = result.color;
    });
  }

  Future<void> _onSave() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<AgentsCubit>();
    // Resolve what gets sent to the API vs. shown in the avatar.
    //   * `file://`         → local fallback when the upload failed; the
    //                         server can't store local paths so we strip
    //                         it from the payload and keep it for display.
    //   * `https://?v=...`  → successful S3 upload with a cache-busting
    //                         query — strip the query before persisting so
    //                         the stored URL stays the canonical S3 key;
    //                         keep the `?v=` version for the avatar so the
    //                         next render fetches fresh bytes.
    //   * preset name       → passed through as-is for both.
    final selected = _iconKey;
    final isLocal = selected?.startsWith('file://') ?? false;
    final String? iconForApi;
    if (selected == null || selected.isEmpty) {
      iconForApi = selected;
    } else if (isLocal) {
      iconForApi = widget.agent.iconKey;
    } else if (selected.startsWith('http://') ||
        selected.startsWith('https://')) {
      iconForApi = _stripQuery(selected);
    } else {
      iconForApi = selected;
    }
    await cubit.updateAgent(
      widget.agent.agentId,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      iconKey: iconForApi,
      iconKeyDisplay: selected,
      iconColor: _colorToHex(_iconColor),
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
                const SizedBox(height: 12),
                _EditIconPicker(
                  selected: _iconKey,
                  selectedColor: _iconColor,
                  enabled: enabled,
                  onSelected: (key) => setState(() => _iconKey = key),
                  onMoreTapped: widget.canEdit ? _openIconBrowser : null,
                ),
                if (widget.canEdit) ...[
                  const SizedBox(height: 12),
                  _SaveButton(
                    isSaving: isSaving,
                    onPressed: canSubmit ? _onSave : null,
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

    // The null item renders [agentTypeLabel] as the placeholder inside the box,
    // so no caption above. Shares the 44px height/style via [AppDropdownField].
    return AppDropdownField<String?>(
      value: value,
      enabled: enabled,
      onChanged: onChanged,
      items: items,
    );
  }
}

/// Compact two-row icon grid for the edit form.
///
/// Mirrors the approve-sheet's `_IconGrid` for preset glyphs, and extends
/// it with the [VaultIconPicker] pattern for custom image URLs: the last
/// preset slot becomes [ImagePresetTile] whenever a custom URL has been
/// picked, even after the user switches back to a preset glyph.
class _EditIconPicker extends StatefulWidget {
  const _EditIconPicker({
    required this.selected,
    required this.selectedColor,
    required this.enabled,
    required this.onSelected,
    required this.onMoreTapped,
  });

  final String? selected;
  final Color selectedColor;
  final bool enabled;
  final ValueChanged<String?> onSelected;
  final VoidCallback? onMoreTapped;

  @override
  State<_EditIconPicker> createState() => _EditIconPickerState();
}

class _EditIconPickerState extends State<_EditIconPicker> {
  String? _savedCustomUrl;

  static bool _isCustomUrl(String? key) {
    if (key == null) return false;
    return key.startsWith('file://') ||
        key.startsWith('https://') ||
        key.startsWith('http://');
  }

  @override
  void initState() {
    super.initState();
    if (_isCustomUrl(widget.selected)) _savedCustomUrl = widget.selected;
  }

  @override
  void didUpdateWidget(_EditIconPicker old) {
    super.didUpdateWidget(old);
    if (_isCustomUrl(widget.selected)) _savedCustomUrl = widget.selected;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final l10n = AppLocalizations.of(context)!;
    final presets = agentIconOptions;
    final customUrl = _savedCustomUrl;
    final isCustomActive = _isCustomUrl(widget.selected);

    // Non-URL browser icon (e.g. "computer") — only inject at last slot when
    // no custom image is saved; if one is saved it occupies that slot.
    final isFromBrowser = !isCustomActive &&
        customUrl == null &&
        widget.selected != null &&
        !presets.contains(widget.selected);
    final effectivePresets = isFromBrowser
        ? [...presets.sublist(0, presets.length - 1), widget.selected!]
        : presets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.agentIconLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceMuted(brightness),
          ),
        ),
        const SizedBox(height: 8),
        Opacity(
          opacity: widget.enabled ? 1.0 : 0.4,
          child: AbsorbPointer(
            absorbing: !widget.enabled,
            child: IconPickerGrid(
              itemCount: effectivePresets.length,
              itemBuilder: (i, isLast) {
                if (customUrl != null && isLast) {
                  return ImagePresetTile(
                    imageUrl: customUrl,
                    selectedColor: widget.selectedColor,
                    isSelected: isCustomActive,
                    onTap: () => widget.onSelected(customUrl),
                  );
                }
                final iconKey = effectivePresets[i];
                return IconPresetTile(
                  icon: agentIconData(iconKey),
                  paletteColor: agentIconColor(iconKey),
                  isSelected: widget.selected == iconKey,
                  selectedColor: widget.selectedColor,
                  onTap: () => widget.onSelected(
                    widget.selected == iconKey ? null : iconKey,
                  ),
                );
              },
              moreTile: widget.onMoreTapped != null
                  ? IconMoreTile(onTap: widget.onMoreTapped!)
                  : null,
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
      height: 44,
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
