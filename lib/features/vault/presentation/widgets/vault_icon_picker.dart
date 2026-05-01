import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/services/vault_icon_upload_service.dart';
import 'vault_visuals.dart';

/// Horizontal row of icon-circles used in vault create / edit forms,
/// followed by an "Upload photo" button.
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
    final l10n = AppLocalizations.of(context)!;
    final choices = VaultVisuals.iconChoices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Upload button above preset icons so it reads as primary action
        if (_showUpload) ...[
          _UploadButton(
            isSelected: _isCustomUrl,
            isUploading: _uploading,
            accentColor: widget.accentColor,
            customUrl: _isCustomUrl ? widget.selected : null,
            label: l10n.vaultIconUpload,
            onTap: _uploading ? null : _pickAndUpload,
          ),
          const SizedBox(height: 10),
        ],

        // Icon preset circles
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

/// Full-width upload button placed below the icon circles.
///
/// When a custom image is selected, shows a thumbnail preview on the left.
/// Uses a dashed border in the idle state so it reads as an action, not
/// just another option.
class _UploadButton extends StatelessWidget {
  const _UploadButton({
    required this.isSelected,
    required this.isUploading,
    required this.accentColor,
    required this.label,
    required this.onTap,
    this.customUrl,
  });

  final bool isSelected;
  final bool isUploading;
  final Color accentColor;
  final String? customUrl;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? AppColors.brandRed
        : AppColors.vaultSlate.withValues(alpha: 0.30);
    final bgColor = isSelected
        ? accentColor.withValues(alpha: 0.06)
        : AppColors.vaultSlate.withValues(alpha: 0.06);

    Widget leading;
    if (isUploading) {
      leading = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.tealAccent),
      );
    } else if (customUrl != null) {
      final isLocal = customUrl!.startsWith('file://');
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: isLocal
            ? Image.file(
                File(customUrl!.replaceFirst('file://', '')),
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => const Icon(
                  Icons.broken_image_outlined,
                  size: 18,
                  color: AppColors.textSecondaryMobile,
                ),
              )
            : Image.network(
                customUrl!,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => const Icon(
                  Icons.broken_image_outlined,
                  size: 18,
                  color: AppColors.textSecondaryMobile,
                ),
              ),
      );
    } else {
      leading = const Icon(
        Icons.add_photo_alternate_outlined,
        size: 18,
        color: AppColors.tealAccent,
      );
    }

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: 1,
              style: isSelected ? BorderStyle.solid : BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? accentColor
                        : AppColors.tealAccent,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: isSelected
                    ? accentColor
                    : AppColors.tealAccent.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
