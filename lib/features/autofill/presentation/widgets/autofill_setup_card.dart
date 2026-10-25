import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/compact_primary_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/autofill_provider_bridge.dart';
import '../cubit/autofill_setup_cubit.dart';

/// Persistent, user-initiated OS provider setup; no local dismissal preference.
class AutoFillSetupCard extends StatefulWidget {
  const AutoFillSetupCard({super.key, this.hideWhenEnabled = false});
  final bool hideWhenEnabled;

  @override
  State<AutoFillSetupCard> createState() => _AutoFillSetupCardState();
}

class _AutoFillSetupCardState extends State<AutoFillSetupCard>
    with WidgetsBindingObserver {
  final _cubit = AutoFillSetupCubit(const AutoFillProviderBridge());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cubit.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cubit.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AutoFillSetupCubit, AutoFillSetupState>(
        bloc: _cubit,
        builder: (context, state) {
          final status = state is AutoFillSetupLoaded ? state.status : null;
          final enabled =
              status == AutoFillProviderStatus.enabled ||
              status == AutoFillProviderStatus.enabledManual;
          if (state is AutoFillSetupLoading ||
              status == AutoFillProviderStatus.unsupported ||
              (widget.hideWhenEnabled && enabled)) {
            return const SizedBox.shrink();
          }
          final brightness = Theme.of(context).brightness;
          final manual =
              status == AutoFillProviderStatus.manual ||
              status == AutoFillProviderStatus.enabledManual;
          final error = state is AutoFillSetupError;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.cardFill(brightness),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: enabled
                      ? AppColors.cardBorder(brightness)
                      : AppColors.vaultPeach,
                ),
              ),
              child: _content(
                context,
                enabled: enabled,
                manual: manual,
                error: error,
              ),
            ),
          );
        },
      );

  Widget _content(
    BuildContext context, {
    required bool enabled,
    required bool manual,
    required bool error,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          enabled ? l10n.autofillEnabled : l10n.autofillSetupTitle,
          style: TextStyle(
            color: AppColors.onSurface(brightness),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          error
              ? l10n.autofillStatusError
              : manual
              ? l10n.autofillManualIos
              : enabled
              ? l10n.autofillEnabledHint
              : l10n.autofillSetupHint,
          style: TextStyle(
            color: AppColors.onSurfaceMuted(brightness),
            fontSize: 12,
            height: 1.35,
          ),
        ),
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.autofillChromeHint,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        CompactPrimaryButton(
          label: manual || error
              ? l10n.autofillCheckAgain
              : l10n.autofillOpenSettings,
          onPressed: manual || error ? _cubit.refresh : _cubit.openSettings,
        ),
      ],
    );
  }
}
