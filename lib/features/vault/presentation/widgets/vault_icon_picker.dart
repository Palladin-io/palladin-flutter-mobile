import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/services/vault_icon_upload_service.dart';
import 'vault_visuals.dart';

/// Horizontal row of icon-circles used in vault create / edit forms.
/// The last circle is the upload action — styled in teal to stand out.
///
/// Two upload modes:
/// - **Edit mode** (`vaultId` + `uploadService` provided): image is uploaded
///   immediately after picking; [onSelected] receives the public URL.
/// - **Create mode** (`onFilePicked` provided): the picked [XFile] is handed
///   to the caller for deferred upload once a vault ID is available.
class VaultIconPicker extends StatefulWidget {
  const VaultIconPicker({
    super.key,
    required this.selected,
    required this.accentColor,
    required this.onSelected,
    this.vaultId,
    this.uploadService,
    this.onFilePicked,
  });

  final String selected;
  final Color accentColor;
  final ValueChanged<String> onSelected;

  /// Edit mode: vault already exists, upload happens immediately.
  final String? vaultId;

  /// Injected for testability; defaults to a new instance in production.
  final VaultIconUploadService? uploadService;

  /// Create mode: called with the picked file so the caller can defer
  /// the upload until after vault creation.
  final ValueChanged<XFile>? onFilePicked;

  @override
  State<VaultIconPicker> createState() => _VaultIconPickerState();
}

class _VaultIconPickerState extends State<VaultIconPicker> {
  bool _uploading = false;
  String? _uploadError;

  bool get _isCustomUrl =>
      widget.selected.startsWith('https://') ||
      widget.selected.startsWith('file://');
  bool get _showUpload =>
      widget.vaultId != null || widget.onFilePicked != null;

  Future<void> _pickAndUpload() async {
    setState(() => _uploadError = null);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 90);
      if (picked == null) return;

      // Create mode — hand off the file for deferred upload.
      if (widget.onFilePicked != null) {
        widget.onFilePicked!(picked);
        widget.onSelected('file://${picked.path}');
        return;
      }

      // Edit mode — upload immediately.
      final vaultId = widget.vaultId;
      final service = widget.uploadService;
      if (vaultId == null || service == null) return;

      setState(() => _uploading = true);
      try {
        final publicUrl = await service.uploadIcon(vaultId, File(picked.path));
        widget.onSelected(publicUrl);
      } on VaultIconUploadException catch (e) {
        setState(() => _uploadError = e.message);
      } catch (_) {
        setState(() => _uploadError = 'Upload failed. Please try again.');
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
    } catch (_) {
      // image_picker channel not available (e.g. simulator without photo library)
      setState(() => _uploadError = 'Photo library not available on this device.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = VaultVisuals.iconChoices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final choice in choices)
              _IconCircle(
                icon: choice.icon,
                isSelected: !_isCustomUrl && choice.name == widget.selected,
                accentColor: widget.accentColor,
                onTap: () => widget.onSelected(choice.name),
              ),
            if (_showUpload)
              _UploadCircle(
                isSelected: _isCustomUrl,
                isUploading: _uploading,
                customUrl: _isCustomUrl ? widget.selected : null,
                onTap: _uploading ? null : _pickAndUpload,
                semanticLabel: AppLocalizations.of(context)!.vaultIconUpload,
              ),
          ],
        ),

        if (_uploadError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _uploadError!,
              style: const TextStyle(fontSize: 11, color: AppColors.brandRed),
            ),
          ),
      ],
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({
    required this.icon,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? accentColor.withValues(alpha: 0.15)
        : AppColors.vaultSlate.withValues(alpha: 0.10);
    final iconColor = isSelected ? accentColor : AppColors.textPrimary;

    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: isSelected
                ? Border.all(color: AppColors.brandRed, width: 2)
                : null,
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}

/// Upload circle — sits at the end of the preset icon row.
/// Teal border + teal icon signal "this is an action", not just another preset.
/// When a custom photo is selected, shows the thumbnail clipped to a circle.
class _UploadCircle extends StatelessWidget {
  const _UploadCircle({
    required this.isSelected,
    required this.isUploading,
    required this.semanticLabel,
    required this.onTap,
    this.customUrl,
  });

  final bool isSelected;
  final bool isUploading;
  final String? customUrl;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const teal = AppColors.tealAccent;

    Widget child;
    if (isUploading) {
      child = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: teal),
      );
    } else if (customUrl != null) {
      final isLocal = customUrl!.startsWith('file://');
      child = ClipOval(
        child: isLocal
            ? Image.file(
                File(customUrl!.replaceFirst('file://', '')),
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => const Icon(
                  Icons.broken_image_outlined,
                  size: 16,
                  color: teal,
                ),
              )
            : Image.network(
                customUrl!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => const Icon(
                  Icons.broken_image_outlined,
                  size: 16,
                  color: teal,
                ),
              ),
      );
    } else {
      child = const Icon(
        Icons.add_photo_alternate_outlined,
        size: 16,
        color: teal,
      );
    }

    final bgColor = isSelected
        ? teal.withValues(alpha: 0.18)
        : teal.withValues(alpha: 0.10);
    final borderColor = isSelected ? AppColors.brandRed : teal;
    final borderWidth = isSelected ? 2.0 : 1.5;

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: child,
        ),
      ),
    );
  }
}
