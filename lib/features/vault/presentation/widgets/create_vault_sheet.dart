import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../data/services/vault_settings_service.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../cubit/create_vault_cubit.dart';
import 'vault_form.dart';
import 'vault_visuals.dart';

/// Bottom sheet that wraps [VaultForm] and the create-vault flow.
///
/// Returns the created [VaultEntity] via `Navigator.pop` so the caller
/// can navigate straight into the new vault, or `null` if the user
/// dismissed the sheet without submitting.
class CreateVaultSheet extends StatelessWidget {
  const CreateVaultSheet({super.key});

  /// Convenience helper — pushes the sheet with the project's default
  /// configuration and returns the created vault (or null on dismiss).
  static Future<VaultEntity?> show(BuildContext context) {
    return showModalBottomSheet<VaultEntity>(
      context: context,
      isScrollControlled: true,
      // useRootNavigator pushes the modal on the root Navigator, above
      // GoRouter's ShellRoute Scaffold. Without this the sheet inherits
      // the Scaffold's adjusted MediaQuery which reserves space for the
      // bottom nav bar, leaving an empty gap at the sheet's bottom.
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateVaultSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CreateVaultCubit>(
      create: (_) => getIt<CreateVaultCubit>(),
      child: const _CreateVaultSheetView(),
    );
  }
}

class _CreateVaultSheetView extends StatefulWidget {
  const _CreateVaultSheetView();

  @override
  State<_CreateVaultSheetView> createState() => _CreateVaultSheetViewState();
}

class _CreateVaultSheetViewState extends State<_CreateVaultSheetView> {
  static const _initialFormData = VaultFormData(
    name: '',
    description: '',
    icon: VaultVisuals.defaultIconName,
    color: VaultVisuals.defaultColorHex,
    grantMode: GrantMode.granular,
  );

  VaultFormData _formData = _initialFormData;
  XFile? _pendingIconFile;
  bool _pickingIcon = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.capture('vault', 'create-sheet-opened');
  }

  Future<String?> _pickIcon() async {
    if (_pickingIcon) return null;
    setState(() => _pickingIcon = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null || !mounted) return null;
      setState(() => _pendingIconFile = file);
      return 'file://${file.path}';
    } finally {
      if (mounted) setState(() => _pickingIcon = false);
    }
  }

  Future<void> _handleSubmit() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.vaultErrorUnknown),
          ),
        );
      return;
    }
    // Defensive copy of the unlocked private key so the cubit can mutate
    // it without touching the auth bloc's state. We zero `keyCopy` in
    // `finally` — `VaultCryptoService` already zeros its own `SecureKey`
    // wrapper, but the raw `Uint8List` we hand it would otherwise linger
    // on the heap with the secret key material.
    final keyCopy = Uint8List.fromList(auth.privateKey!);
    VaultEntity? vault;
    try {
      // Don't send file:// path to the API — icon upload happens after create.
      final iconForApi = _pendingIconFile != null ? null : _formData.icon;
      await context.read<CreateVaultCubit>().createVault(
        name: _formData.name,
        description: _formData.description,
        icon: iconForApi,
        color: _formData.color,
        grantMode: _formData.grantMode,
        privateKey: keyCopy,
      );
      if (!mounted) return;
      final cubitState = context.read<CreateVaultCubit>().state;
      if (cubitState is! CreateVaultSuccess) return;
      vault = cubitState.vault;
      if (_pendingIconFile != null) {
        try {
          vault = await getIt<VaultSettingsService>().update(
            expected: vault,
            name: vault.name,
            description: vault.description ?? '',
            icon: vault.icon ?? '',
            color: vault.color ?? _formData.color,
            memberPrivateKey: keyCopy,
            localIconPath: _pendingIconFile!.path,
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context)!.vaultIconUploadError,
                  ),
                ),
              );
          }
        }
      }
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
    if (mounted && vault != null) Navigator.of(context).pop(vault);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return BlocBuilder<CreateVaultCubit, CreateVaultState>(
      builder: (context, state) {
        final isLoading = state is CreateVaultLoading;
        final isBusy = isLoading || _pickingIcon;
        final canSubmit = !isBusy && _formData.name.trim().isNotEmpty;

        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.modalBackground(brightness),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Padding(
              // Use the device's physical bottom inset so the sheet hugs
              // the home indicator instead of floating above the
              // shell-reserved bottom-nav space.
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.md,
                  AppSpacing.screenH,
                  AppSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SheetHandle(),
                    const SizedBox(height: AppSpacing.xxl),
                    _SheetHeader(
                      title: l10n.vaultNewVault,
                      onClose: isBusy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: AppSpacing.headerGap),
                    Flexible(
                      child: SingleChildScrollView(
                        child: VaultForm(
                          initial: _initialFormData,
                          onChanged: (data) => setState(() => _formData = data),
                          onPickCustomIcon: isBusy
                              ? () async => null
                              : _pickIcon,
                        ),
                      ),
                    ),
                    if (_pickingIcon)
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.innerGap),
                        child: LinearProgressIndicator(
                          color: AppColors.brandRed,
                          backgroundColor: AppColors.hairline,
                        ),
                      ),
                    if (state is CreateVaultError) ...[
                      const SizedBox(height: AppSpacing.fieldGap),
                      Text(
                        _errorMessage(context, state.kind),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.brandRed,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.section),
                    PrimaryButton(
                      label: isLoading
                          ? l10n.vaultCreating
                          : l10n.vaultNewVault,
                      isLoading: isLoading,
                      onPressed: canSubmit ? _handleSubmit : null,
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

  String _errorMessage(BuildContext context, VaultErrorKind kind) {
    final l10n = AppLocalizations.of(context)!;
    return switch (kind) {
      VaultErrorKind.notFound => l10n.vaultErrorNotFound,
      VaultErrorKind.forbidden => l10n.vaultErrorForbidden,
      VaultErrorKind.planLimitReached => l10n.vaultErrorPlanLimitReached,
      VaultErrorKind.fullModeNotAllowed => l10n.vaultErrorFullModeNotAllowed,
      VaultErrorKind.networkError => l10n.errorCannotConnectToServer,
      VaultErrorKind.conflict => l10n.vaultMetadataConflict,
      VaultErrorKind.corrupt => l10n.vaultMetadataCorrupt,
      VaultErrorKind.unknown => l10n.vaultErrorUnknown,
    };
  }
}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.onSurfaceSubtle(brightness).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.close, color: AppColors.onSurfaceMuted(brightness)),
          onPressed: onClose,
          tooltip: MaterialLocalizations.of(context).closeButtonLabel,
        ),
      ],
    );
  }
}
