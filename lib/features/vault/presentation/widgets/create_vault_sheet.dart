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
    icon: '🔒',
    color: '#48ECDF',
    grantMode: GrantMode.granular,
  );

  VaultFormData _formData = _initialFormData;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.capture('vault', 'create-sheet-opened');
  }

  void _handleSubmit() {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      // Should be impossible — the sheet is only reachable when the
      // vault is unlocked. Surface a generic error instead of crashing.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.vaultErrorUnknown),
        ));
      return;
    }
    AnalyticsService.instance.capture('vault', 'create-submitted');
    context.read<CreateVaultCubit>().createVault(
          name: _formData.name,
          description: _formData.description,
          icon: _formData.icon,
          color: _formData.color,
          grantMode: _formData.grantMode,
          privateKey: Uint8List.fromList(auth.privateKey!),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return BlocConsumer<CreateVaultCubit, CreateVaultState>(
      listenWhen: (previous, current) => current is CreateVaultSuccess,
      listener: (context, state) {
        if (state is CreateVaultSuccess) {
          AnalyticsService.instance.capture('vault', 'create-succeeded');
          Navigator.of(context).pop(state.vault);
        }
      },
      builder: (context, state) {
        final isLoading = state is CreateVaultLoading;
        final canSubmit = !isLoading && _formData.name.trim().isNotEmpty;

        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.darkBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SheetHandle(),
                    const SizedBox(height: 12),
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
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.textTertiary.withValues(alpha: 0.4),
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
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: onClose,
          tooltip: MaterialLocalizations.of(context).closeButtonLabel,
        ),
      ],
    );
  }
}
