import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../domain/entities/entry_entity.dart';

/// Shared form widgets for Add Entry / Edit Entry pages.
///
/// All five widgets here were duplicated 1:1 between
/// `add_entry_page.dart` and `entry_detail_page.dart` — the diff was
/// pure boilerplate. Extracting them here keeps the form pages focused
/// on flow logic instead of styling and lets the picker/toggle look stay
/// in sync across both screens automatically.

/// Dropdown selector for the entry type (Key / Credential).
///
/// Wired with the same fill / border / dropdown colors as the rest of
/// the form so the dropdown matches the surrounding `OnboardingTextField`s.
class EntryTypeDropdown extends StatelessWidget {
  const EntryTypeDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final EntryType value;
  final ValueChanged<EntryType?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.entryTypeLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceMuted(brightness),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.inputFill(brightness),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.inputBorder(brightness),
              width: 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<EntryType>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.modalBackground(brightness),
              iconEnabledColor: AppColors.onSurfaceMuted(brightness),
              style: TextStyle(
                color: AppColors.inputText(brightness),
                fontSize: 14,
              ),
              items: [
                DropdownMenuItem(
                  value: EntryType.credential,
                  child: Text(l10n.entryTypeCredential),
                ),
                DropdownMenuItem(
                  value: EntryType.key,
                  child: Text(l10n.entryTypeKey),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Eye-toggle button used as the suffix icon of password / secret fields.
class EntryObscureToggle extends StatelessWidget {
  const EntryObscureToggle({
    super.key,
    required this.obscured,
    required this.onPressed,
  });

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscured ? Icons.visibility : Icons.visibility_off,
        size: 18,
        color: AppColors.textTertiaryMobile,
      ),
      onPressed: onPressed,
      splashRadius: 18,
      tooltip: AppLocalizations.of(context)!.vaultRevealValue,
    );
  }
}

/// Multi-line notes field — thin wrapper around [OnboardingTextField]
/// with `maxLines: 3` so notes inputs look identical to single-line
/// fields elsewhere on the form.
class EntryNotesField extends StatelessWidget {
  const EntryNotesField({
    super.key,
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OnboardingTextField(
      controller: controller,
      label: label,
      textCapitalization: TextCapitalization.sentences,
      maxLines: 3,
    );
  }
}

/// Reassurance banner shown above the save button — calls out that the
/// secret is encrypted on-device before upload.
class EntryEncryptionNotice extends StatelessWidget {
  const EntryEncryptionNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tealAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.tealAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline,
            size: 16,
            color: AppColors.tealAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.tealAccent,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin wrapper around [PrimaryButton] that swaps the label for the
/// "saving…" copy while [isLoading] is true. Used as the Save action on
/// both Add Entry and Edit Entry forms.
class EntrySaveButton extends StatelessWidget {
  const EntrySaveButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
  });

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PrimaryButton(
      label: isLoading ? l10n.entrySaving : l10n.entrySaveAction,
      isLoading: isLoading,
      onPressed: onPressed,
    );
  }
}

/// Upload button shown below the entry icon picker.
/// Displays a thumbnail preview when a custom icon URL is already selected.
class UploadIconButton extends StatelessWidget {
  const UploadIconButton({
    super.key,
    required this.accentColor,
    required this.onTap,
    this.imageUrl,
    this.isLoading = false,
  });

  final Color accentColor;
  final VoidCallback? onTap;
  final String? imageUrl;
  final bool isLoading;

  bool get _hasImage => imageUrl != null;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _hasImage
              ? accentColor.withValues(alpha: 0.08)
              : AppColors.onSurface(brightness).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hasImage
                ? accentColor.withValues(alpha: 0.3)
                : AppColors.cardBorder(brightness),
          ),
        ),
        child: Row(
          children: [
            if (isLoading)
              SizedBox(
                width: 15, height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              )
            else
              Icon(
                Icons.file_upload_outlined,
                size: 15,
                color: _hasImage
                    ? accentColor
                    : AppColors.onSurfaceSubtle(brightness),
              ),
            const SizedBox(width: 8),
            Text(
              l10n.vaultIconUpload,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _hasImage
                    ? accentColor
                    : AppColors.onSurfaceSubtle(brightness),
              ),
            ),
            if (_hasImage) ...[
              const Spacer(),
              _SmallPreview(imageUrl: imageUrl!, accentColor: accentColor),
            ],
          ],
        ),
      ),
    );
  }
}

class _SmallPreview extends StatelessWidget {
  const _SmallPreview({required this.imageUrl, required this.accentColor});

  final String imageUrl;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (imageUrl.startsWith('file://')) {
      child = Image.file(
        File(imageUrl.substring(7)),
        width: 28, height: 28, fit: BoxFit.cover,
        errorBuilder: (_, e, s) => const Icon(Icons.image, size: 16),
      );
    } else {
      child = Image.network(
        imageUrl,
        width: 28, height: 28, fit: BoxFit.cover,
        errorBuilder: (_, e, s) => const Icon(Icons.image, size: 16),
      );
    }
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
