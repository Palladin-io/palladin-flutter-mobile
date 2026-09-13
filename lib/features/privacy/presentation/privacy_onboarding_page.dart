import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import 'consent_choices.dart';
import 'consent_cubit.dart';

/// Optional startup layer, before the router's existing setup/verification gates.
class PrivacyOnboardingPage extends StatefulWidget {
  const PrivacyOnboardingPage({super.key, this.onCompleted});
  final VoidCallback? onCompleted;
  @override
  State<PrivacyOnboardingPage> createState() => _PrivacyOnboardingPageState();
}

class _PrivacyOnboardingPageState extends State<PrivacyOnboardingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final cubit = context.read<ConsentCubit>();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: AppColors.modalBackground(Theme.of(context).brightness),
      builder: (sheetContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<ConsentCubit, ConsentState>(
          builder: (context, state) => PopScope(
            canPop: !state.saving,
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .9,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      AppSpacing.lg,
                      AppSpacing.screenH,
                      AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppLocalizations.of(
                              sheetContext,
                            )!.privacyOnboardingTitle,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(
                            sheetContext,
                          ).closeButtonTooltip,
                          onPressed: state.saving
                              ? null
                              : () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ConsentChoices(
                      source: 'mobile_onboarding',
                      onContinue: () => Navigator.pop(sheetContext, true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved != true) await cubit.stopHere();
    if (!mounted) return;
    if (widget.onCompleted case final complete?) {
      complete();
    } else {
      context.read<AuthBloc>().add(const PrivacyChoicesCompleted());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.cardFill(Theme.of(context).brightness),
    body: const SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            'Palladin',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ),
  );
}
