import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/compact_primary_button.dart';
import '../../../../core/widgets/setup_card.dart';
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
          final chromeSetup =
              enabled &&
              state is AutoFillSetupLoaded &&
              state.chromeStatus == ChromeAutoFillStatus.disabled;
          if (state is AutoFillSetupLoading ||
              status == AutoFillProviderStatus.unsupported ||
              (widget.hideWhenEnabled && enabled && !chromeSetup)) {
            return const SizedBox.shrink();
          }
          final manual =
              status == AutoFillProviderStatus.manual ||
              status == AutoFillProviderStatus.enabledManual;
          final error = state is AutoFillSetupError;
          return _content(
            context,
            enabled: enabled,
            manual: manual,
            error: error,
            chromeSetup: chromeSetup,
            chromeSettingsFailed:
                state is AutoFillSetupLoaded && state.chromeSettingsFailed,
          );
        },
      );

  Widget _content(
    BuildContext context, {
    required bool enabled,
    required bool manual,
    required bool error,
    required bool chromeSetup,
    required bool chromeSettingsFailed,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return SetupCard(
      title: chromeSetup
          ? l10n.autofillChromeSetupTitle
          : enabled
          ? l10n.autofillEnabled
          : l10n.autofillSetupTitle,
      borderColor: enabled && !chromeSetup ? null : AppColors.vaultPeach,
      descriptions: [
        chromeSettingsFailed
            ? l10n.autofillChromeSettingsError
            : chromeSetup
            ? l10n.autofillChromeSetupHint
            : error
            ? l10n.autofillStatusError
            : manual
            ? l10n.autofillManualIos
            : enabled
            ? l10n.autofillEnabledHint
            : l10n.autofillSetupHint,
        if (chromeSettingsFailed) l10n.autofillChromeSetupHint,
        if (defaultTargetPlatform == TargetPlatform.android && !chromeSetup)
          l10n.autofillChromeHint,
      ],
      actions: [
        CompactPrimaryButton(
          label: chromeSetup
              ? l10n.autofillOpenChromeSettings
              : manual || error
              ? l10n.autofillCheckAgain
              : l10n.autofillOpenSettings,
          onPressed: chromeSetup
              ? _cubit.openChromeSettings
              : manual || error
              ? _cubit.refresh
              : _cubit.openSettings,
        ),
      ],
    );
  }
}
