import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/services/vault_icon_upload_service.dart';
import 'vault_visuals.dart';

/// Horizontal row of icon-circles used in vault create / edit forms.
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

  bool get _isCustomUrl => widget.selected.startsWith('https://');
  bool get _showUpload =>
      widget.vaultId != null || widget.onFilePicked != null;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    // Create mode — hand off the file for deferred upload.
    if (widget.onFilePicked != null) {
      widget.onFilePicked!(picked);
      // Show a local preview via a fake placeholder URL so the circle
      // reflects the chosen image (replaced by the real URL post-create).
      widget.onSelected('file://${picked.path}');
      return;
    }

    // Edit mode — upload immediately.
    final vaultId = widget.vaultId;
    final service = widget.uploadService;
    if (vaultId == null || service == null) return;

    setState(() {
      _uploading = true;
      _uploadError = null;
    });

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
                accentColor: widget.accentColor,
                customUrl: _isCustomUrl ? widget.selected : null,
                onTap: _pickAndUpload,
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

class _UploadCircle extends StatelessWidget {
  const _UploadCircle({
    required this.isSelected,
    required this.isUploading,
    required this.accentColor,
    required this.onTap,
    this.customUrl,
  });

  final bool isSelected;
  final bool isUploading;
  final Color accentColor;
  final String? customUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? accentColor.withValues(alpha: 0.15)
        : AppColors.vaultSlate.withValues(alpha: 0.10);

    Widget child;
    if (isUploading) {
      child = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.tealAccent),
      );
    } else if (customUrl != null) {
      final isLocal = customUrl!.startsWith('file://');
      child = ClipOval(
        child: isLocal
            ? Image.file(
                File(customUrl!.replaceFirst('file://', '')),
                width: 22,
                height: 22,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => const Icon(
                  Icons.broken_image_outlined,
                  size: 16,
                  color: AppColors.textPrimary,
                ),
              )
            : Image.network(
                customUrl!,
                width: 22,
                height: 22,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => const Icon(
                  Icons.broken_image_outlined,
                  size: 16,
                  color: AppColors.textPrimary,
                ),
              ),
      );
    } else {
      child = const Icon(Icons.upload_outlined, size: 16, color: AppColors.textPrimary);
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Upload custom icon',
      child: GestureDetector(
        onTap: isUploading ? null : onTap,
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
                : Border.all(
                    color: AppColors.vaultSlate.withValues(alpha: 0.20),
                    width: 1,
                    style: BorderStyle.solid,
                  ),
          ),
          child: child,
        ),
      ),
    );
  }
}
