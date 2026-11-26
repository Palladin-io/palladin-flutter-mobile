import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/action_zone.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_action_footer.dart';
import '../../../../core/widgets/primary_button.dart';
import 'entry_field_row.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'vault_form.dart';

/// Vault metadata uses the same read-only and full-screen edit flow as Entries.
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
  final Future<bool> Function()? onSave;

  @override
  State<VaultSettingsTab> createState() => _VaultSettingsTabState();
}

class _VaultSettingsTabState extends State<VaultSettingsTab> {
  Future<void> _edit() async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => _VaultEditPage(
          initial: widget.initial,
          onChanged: widget.onChanged,
          onSave: widget.onSave!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final b = Theme.of(context).brightness;
    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.only(
            top: AppSpacing.section,
            bottom: widget.onSave == null
                ? AppSpacing.section
                : AppFab.scrollClearance(context),
          ),
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardFill(b),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder(b)),
              ),
              child: Column(
                children: [
                  EntryFieldRow(
                    icon: Icons.shield_outlined,
                    value: widget.initial.name,
                    isMasked: false,
                    revealed: true,
                    onToggleReveal: null,
                    onCopy: null,
                  ).labeled(l10n.vaultNameLabel),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.cardBorder(b),
                  ),
                  EntryFieldRow(
                    icon: Icons.notes,
                    value: widget.initial.description,
                    isMasked: false,
                    revealed: true,
                    onToggleReveal: null,
                    onCopy: null,
                    multiline: true,
                  ).labeled(l10n.vaultDescriptionLabel),
                ],
              ),
            ),
            if (widget.onDelete != null) ...[
              const SizedBox(height: AppSpacing.section),
              CompactDangerZone(
                title: l10n.entryDangerZone,
                heading: l10n.vaultDeleteVault,
                onPressed: widget.onDelete,
              ),
            ],
          ],
        ),
        if (widget.onSave != null)
          Positioned(
            right: 0,
            bottom: AppFab.overlayInset(context),
            child: AppFab(
              onPressed: _edit,
              tooltip: l10n.entryEditAction,
              icon: Icons.edit_outlined,
            ),
          ),
      ],
    );
  }
}

class _VaultEditPage extends StatefulWidget {
  const _VaultEditPage({
    required this.initial,
    required this.onChanged,
    required this.onSave,
  });
  final VaultFormData initial;
  final ValueChanged<VaultFormData> onChanged;
  final Future<bool> Function() onSave;
  @override
  State<_VaultEditPage> createState() => _VaultEditPageState();
}

class _VaultEditPageState extends State<_VaultEditPage> {
  late VaultFormData _data = widget.initial;
  bool _busy = false;
  bool _failed = false;
  bool _picking = false;
  Future<String?> _pick() async {
    if (_picking) return null;
    _picking = true;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      return file == null ? null : Uri.file(file.path).toString();
    } finally {
      _picking = false;
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    widget.onChanged(_data);
    final saved = await widget.onSave();
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppScreen.appBar(
      gapAfterHeader: false,
      safeAreaBottom: false,
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: AppBarTitle(
          title: l10n.entryEditAction,
          subtitle: widget.initial.name,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.section,
                AppSpacing.screenH,
                AppSpacing.section,
              ),
              child: AbsorbPointer(
                absorbing: _busy,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    VaultForm(
                      initial: widget.initial,
                      onChanged: (data) => setState(() => _data = data),
                      onPickCustomIcon: _pick,
                    ),
                    if (_failed) ...[
                      const SizedBox(height: AppSpacing.section),
                      Text(
                        l10n.vaultErrorUnknown,
                        style: const TextStyle(color: AppColors.brandRed),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          AppActionFooter(
            child: PrimaryButton(
              label: l10n.vaultSaveAction,
              isLoading: _busy,
              onPressed:
                  _busy || _data == widget.initial || _data.name.trim().isEmpty
                  ? null
                  : _save,
            ),
          ),
        ],
      ),
    );
  }
}
