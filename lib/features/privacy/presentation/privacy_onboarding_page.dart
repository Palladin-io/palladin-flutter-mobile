import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_screen.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import 'consent_choices.dart';
import 'consent_cubit.dart';

class PrivacyOnboardingPage extends StatelessWidget {
  const PrivacyOnboardingPage({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final saving = context.watch<ConsentCubit>().state.saving;
    final brightness = Theme.of(context).brightness;
    return AppScreen.titled(
      title: l10n.privacyTitle,
      subtitle: l10n.privacySubtitle,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenH,
              ),
              children: const [ConsentChoices(source: 'mobile_onboarding')],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.md,
              AppSpacing.screenH,
              AppSpacing.screenBottom,
            ),
            decoration: BoxDecoration(
              color: AppColors.cardFill(brightness),
              border: Border(
                top: BorderSide(color: AppColors.navBorder(brightness)),
              ),
            ),
            child: PrimaryButton(
              label: l10n.privacyContinue,
              onPressed: saving
                  ? null
                  : () => context.read<AuthBloc>().add(
                      const PrivacyChoicesCompleted(),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
