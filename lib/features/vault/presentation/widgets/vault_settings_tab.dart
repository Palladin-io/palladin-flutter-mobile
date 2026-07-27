import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'vault_form.dart';

/// Settings tab body — wraps [VaultForm] and adds a prominent Save
/// button and a danger zone with the destructive "Delete Vault" button.
///
/// Save action is shown as a full-width button inside the scroll view
/// (above the danger zone) when the form is dirty. The AppBar also has
/// a small TextButton affordance for the same action — both call
/// [onSave].
///
/// Custom icon bytes remain local until Save encrypts them with a Vault-
/// derived key. The backend never receives plaintext image bytes or URLs.
class VaultSettingsTab extends StatefulWidget {
  const VaultSettingsTab({
    super.key,
    required this.vaultId,
    required this.initial,
    required this.onChanged,
    required this.onDelete,
    this.onSave,
  });

  final String vaultId;
  final VaultFormData initial;
  final ValueChanged<VaultFormData> onChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onSave;

  @override
  State<VaultSettingsTab> createState() => _VaultSettingsTabState();
}

class _VaultSettingsTabState extends State<VaultSettingsTab> {
  bool _pickingIcon = false;
  late VaultFormData _currentData;

  @override
  void initState() {
    super.initState();
    _currentData = widget.initial;
  }

  bool get _isDirty => _currentData != widget.initial;

  void _onFormChanged(VaultFormData data) {
    setState(() => _currentData = data);
    widget.onChanged(data);
  }

  Future<String?> _pickAndUploadIcon() async {
    if (_pickingIcon) return null;
    setState(() => _pickingIcon = true);
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    } finally {
      if (mounted) setState(() => _pickingIcon = false);
    }
    if (file == null || !mounted) return null;
    final localReference = Uri.file(file.path).toString();
    _onFormChanged(widget.initial.copyWith(icon: localReference));
    return localReference;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.screenBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VaultForm(
            initial: widget.initial,
            onChanged: _onFormChanged,
            onPickCustomIcon: _pickAndUploadIcon,
          ),
          const SizedBox(height: AppSpacing.section),
          _SaveButton(onSave: _isDirty ? widget.onSave : null, l10n: l10n),
          const SizedBox(height: AppSpacing.section),
          _DangerZone(l10n: l10n, onDelete: widget.onDelete),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.onSave, required this.l10n});

  /// Null when no changes have been made — button renders as disabled.
  final VoidCallback? onSave;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: onSave,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandRed,
          disabledBackgroundColor: AppColors.brandRed.withValues(alpha: 0.35),
          foregroundColor: AppColors.onBrandRed,
          disabledForegroundColor: AppColors.onBrandRed.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: Text(
          l10n.vaultSaveAction,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.l10n, required this.onDelete});

  final AppLocalizations l10n;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.vaultDangerZone,
            style: const TextStyle(
              color: AppColors.brandRed,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton.icon(
              icon: const Icon(
                Icons.delete,
                size: 14,
                color: AppColors.brandRed,
              ),
              label: Text(
                l10n.vaultDeleteVault,
                style: const TextStyle(
                  color: AppColors.brandRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.brandRed.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}
