import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/storage/biometric_key_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/compact_primary_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../cubit/biometric_setup_cubit.dart';

class BiometricSetupCard extends StatefulWidget {
  const BiometricSetupCard({super.key, this.hideWhenHandled = false});
  final bool hideWhenHandled;
  @override
  State<BiometricSetupCard> createState() => _BiometricSetupCardState();
}

class _BiometricSetupCardState extends State<BiometricSetupCard> {
  BiometricSetupCubit? _cubit;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final auth = context.read<AuthBloc>();
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final cubit = BiometricSetupCubit(
      keyStore: getIt<BiometricKeyStore>(),
      preferences: preferences,
      currentAuth: () => auth.state,
    );
    setState(() => _cubit = cubit);
    await cubit.refresh();
  }

  @override
  void dispose() {
    _cubit?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _cubit;
    if (cubit == null) return const SizedBox.shrink();
    return BlocBuilder<BiometricSetupCubit, BiometricSetupState>(
      bloc: cubit,
      builder: (context, state) {
        final enabled = state.status == BiometricSetupStatus.enabled;
        if (state.status == BiometricSetupStatus.unavailable ||
            (widget.hideWhenHandled && (enabled || state.dismissed))) {
          return const SizedBox.shrink();
        }
        return _content(context, cubit, state, enabled);
      },
    );
  }

  Widget _content(
    BuildContext context,
    BiometricSetupCubit cubit,
    BiometricSetupState state,
    bool enabled,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.cardFill(brightness),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder(brightness)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.biometricSetupTitle,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.failed
                  ? l10n.biometricSetupFailed
                  : enabled
                  ? l10n.biometricSetupEnabled
                  : l10n.biometricSetupHint,
              style: TextStyle(
                color: AppColors.onSurfaceMuted(brightness),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            CompactPrimaryButton(
              label: enabled
                  ? l10n.biometricSetupDisable
                  : l10n.biometricSetupEnable,
              onPressed: state.busy
                  ? null
                  : () => enabled
                        ? cubit.disable()
                        : cubit.enable(
                            BiometricPromptCopy(
                              promptTitle: l10n.unlockBiometricPromptTitle,
                              enrollTitle: l10n.unlockBiometricEnrollPrompt,
                              accessTitle: l10n.unlockBiometricPrompt,
                              cancelLabel: l10n.vaultCancel,
                            ),
                          ),
            ),
            if (widget.hideWhenHandled && !enabled)
              TextButton(
                onPressed: state.busy ? null : cubit.dismiss,
                child: Text(l10n.biometricSetupNotNow),
              ),
          ],
        ),
      ),
    );
  }
}
