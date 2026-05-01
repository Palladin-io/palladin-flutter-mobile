import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../cubit/vault_detail_cubit.dart';
import '../widgets/vault_form.dart';

/// Vault settings — edit metadata or delete the vault.
///
/// On delete, navigates back to the vault list. On save, refreshes the
/// detail screen by re-fetching from the cubit.
class VaultSettingsPage extends StatelessWidget {
  const VaultSettingsPage({super.key, required this.vaultId});

  final String vaultId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VaultDetailCubit>(
      create: (_) => getIt<VaultDetailCubit>()..load(vaultId),
      child: _VaultSettingsView(vaultId: vaultId),
    );
  }
}

class _VaultSettingsView extends StatefulWidget {
  const _VaultSettingsView({required this.vaultId});

  final String vaultId;

  @override
  State<_VaultSettingsView> createState() => _VaultSettingsViewState();
}

class _VaultSettingsViewState extends State<_VaultSettingsView> {
  VaultFormData? _formData;
  VaultFormData? _initialData;

  bool get _isDirty {
    final current = _formData;
    final initial = _initialData;
    if (current == null || initial == null) return false;
    return current.name != initial.name ||
        current.description != initial.description ||
        current.icon != initial.icon ||
        current.color != initial.color ||
        current.grantMode != initial.grantMode;
  }

  void _onChanged(VaultFormData data) {
    setState(() => _formData = data);
  }

  void _saveChanges() {
    final data = _formData;
    if (data == null) return;
    context.read<VaultDetailCubit>().update(
          widget.vaultId,
          name: data.name.trim(),
          description: data.description.trim(),
          icon: data.icon,
          color: data.color,
          grantMode: data.grantMode,
        );
  }

  Future<void> _confirmDelete(BuildContext context, String name) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.darkSurface,
          title: Text(
            l10n.vaultDeleteTitle,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          content: Text(
            l10n.vaultDeleteConfirmWithName(name),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                l10n.vaultCancel,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                l10n.vaultDeleteVault,
                style: const TextStyle(color: AppColors.brandRed),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      // Use the cubit available higher in the tree — `context` here is
      // the page's element, which sits above the AlertDialog.
      // ignore: use_build_context_synchronously
      context.read<VaultDetailCubit>().delete(widget.vaultId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocConsumer<VaultDetailCubit, VaultDetailState>(
      listener: (context, state) {
        if (state is VaultDetailLoaded) {
          final next = _formDataFromVault(state.vault);
          // Sync the form once the initial load completes (or after a
          // save round-trip). Avoid clobbering in-flight edits if the
          // cubit re-emits Loaded for the same data.
          if (_initialData == null) {
            setState(() {
              _initialData = next;
              _formData = next;
            });
          } else if (next != _initialData) {
            // Server-side change (e.g. just-saved update). Re-sync both
            // baseline and current form so dirty-state resets.
            setState(() {
              _initialData = next;
              _formData = next;
            });
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text(l10n.vaultSavedSnackbar),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ));
          }
        } else if (state is VaultDetailDeleted) {
          // Navigate back to the list. The list cubit re-loads on
          // next mount via the FAB-create path; for delete-from-
          // settings we still want it fresh, so pop until /.
          context.go('/');
        }
      },
      builder: (context, state) {
        final isLoading = state is VaultDetailLoading;
        final hasError = state is VaultDetailError;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: AppColors.darkSurface,
            title: Text(l10n.vaultSettings),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => context.pop(),
            ),
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: AppColors.darkBackgroundGradient,
            ),
            child: SafeArea(
              top: false,
              child: _formData == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.tealAccent,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          VaultForm(
                            initial: _initialData!,
                            onChanged: _onChanged,
                          ),
                          if (hasError) ...[
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage(context, state.kind),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.brandRed,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          PrimaryButton(
                            label: isLoading
                                ? l10n.vaultSaving
                                : l10n.vaultSaveChanges,
                            isLoading: isLoading,
                            onPressed: (!isLoading && _isDirty)
                                ? _saveChanges
                                : null,
                          ),
                          const SizedBox(height: 32),
                          _DangerZone(
                            onDelete: isLoading
                                ? null
                                : () => _confirmDelete(
                                      context,
                                      _formData!.name,
                                    ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  VaultFormData _formDataFromVault(VaultEntity vault) {
    return VaultFormData(
      name: vault.name,
      description: vault.description ?? '',
      icon: vault.icon ?? '🔒',
      color: vault.color ?? '#48ECDF',
      grantMode: vault.grantMode,
    );
  }

  String _errorMessage(BuildContext context, VaultErrorKind kind) {
    final l10n = AppLocalizations.of(context)!;
    return switch (kind) {
      VaultErrorKind.notFound => l10n.vaultErrorNotFound,
      VaultErrorKind.forbidden => l10n.vaultErrorForbidden,
      VaultErrorKind.planLimitReached => l10n.vaultErrorPlanLimitReached,
      VaultErrorKind.fullModeNotAllowed => l10n.vaultErrorFullModeNotAllowed,
      VaultErrorKind.networkError => l10n.errorCannotConnectToServer,
      VaultErrorKind.unknown => l10n.vaultErrorUnknown,
    };
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.onDelete});

  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.brandRed.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.vaultDangerZone,
            style: const TextStyle(
              color: AppColors.brandRed,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.vaultDangerZoneSubtitle,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.brandRed, size: 18),
              label: Text(
                l10n.vaultDeleteVault,
                style: const TextStyle(
                  color: AppColors.brandRed,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide(
                  color: AppColors.brandRed.withValues(alpha: 0.4),
                ),
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
