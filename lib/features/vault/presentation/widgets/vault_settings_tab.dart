import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'vault_form.dart';

/// Settings tab body — wraps [VaultForm] and adds a danger zone with
/// the destructive "Delete Vault" button.
///
/// Save action lives on the AppBar (parent decides when it's enabled
/// and what it does), so this widget purely renders the form + danger
/// zone.
class VaultSettingsTab extends StatelessWidget {
  const VaultSettingsTab({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.onDelete,
  });

  final VaultFormData initial;
  final ValueChanged<VaultFormData> onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VaultForm(initial: initial, onChanged: onChanged),
          const SizedBox(height: 24),
          _DangerZone(
            l10n: l10n,
            onDelete: onDelete,
          ),
        ],
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
      padding: const EdgeInsets.all(12),
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton.icon(
              icon: const Icon(Icons.delete, size: 14, color: AppColors.brandRed),
              label: Text(
                l10n.vaultDeleteVault,
                style: const TextStyle(
                  color: AppColors.brandRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor:
                    AppColors.brandRed.withValues(alpha: 0.12),
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
