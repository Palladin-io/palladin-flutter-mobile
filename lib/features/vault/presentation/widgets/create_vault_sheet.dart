import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
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

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.capture('vault', 'create-sheet-opened');
  }

  Future<void> _handleSubmit() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.vaultErrorUnknown),
        ));
      return;
    }
    // Defensive copy of the unlocked private key so the cubit can mutate
    // it without touching the auth bloc's state. We zero `keyCopy` in
    // `finally` — `VaultCryptoService` already zeros its own `SecureKey`
    // wrapper, but the raw `Uint8List` we hand it would otherwise linger
    // on the heap with the secret key material.
    final keyCopy = Uint8List.fromList(auth.privateKey!);
    try {
      await context.read<CreateVaultCubit>().createVault(
            name: _formData.name,
            description: _formData.description,
            icon: _formData.icon,
            color: _formData.color,
            grantMode: _formData.grantMode,
            privateKey: keyCopy,
          );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return BlocConsumer<CreateVaultCubit, CreateVaultState>(
      listenWhen: (previous, current) => current is CreateVaultSuccess,
      listener: (context, state) {
        if (state is CreateVaultSuccess) {
          Navigator.of(context).pop(state.vault);
        }
      },
      builder: (context, state) {
        final isLoading = state is CreateVaultLoading;
        final canSubmit = !isLoading && _formData.name.trim().isNotEmpty;

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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SheetHandle(),
                    const SizedBox(height: 24),
                    _SheetHeader(
                      title: l10n.vaultNewVault,
                      onClose: isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: VaultForm(
                          initial: _initialFormData,
                          onChanged: (data) => setState(() => _formData = data),
                        ),
                      ),
                    ),
                    if (state is CreateVaultError) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage(context, state.kind),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.brandRed,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
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
