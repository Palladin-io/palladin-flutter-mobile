import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
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
    return AppDropdownField<EntryType>(
      label: l10n.entryTypeLabel,
      value: value,
      onChanged: onChanged,
      items: [
        DropdownMenuItem(
          value: EntryType.credential,
          child: Text(l10n.entryTypeCredential),
        ),
        DropdownMenuItem(
          value: EntryType.key,
          child: Text(l10n.entryTypeKey),
        ),
        DropdownMenuItem(
          value: EntryType.script,
          child: Text(l10n.entryTypeScript),
        ),
      ],
    );
  }
}

/// Dropdown selector for a script entry's interpreter (bash / sh / node /
/// python).
class EntryInterpreterDropdown extends StatelessWidget {
  const EntryInterpreterDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ScriptInterpreter value;
  final ValueChanged<ScriptInterpreter?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppDropdownField<ScriptInterpreter>(
      label: l10n.entryInterpreterLabel,
      value: value,
      onChanged: onChanged,
      items: const [
        DropdownMenuItem(
          value: ScriptInterpreter.bash,
          child: Text('bash'),
        ),
        DropdownMenuItem(
          value: ScriptInterpreter.sh,
          child: Text('sh'),
        ),
        DropdownMenuItem(
          value: ScriptInterpreter.node,
          child: Text('node'),
        ),
        DropdownMenuItem(
          value: ScriptInterpreter.python,
          child: Text('python'),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.innerGap,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.brandRed.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline,
            size: 16,
            color: AppColors.brandRed,
          ),
          const SizedBox(width: AppSpacing.innerGap),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.brandRed,
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

