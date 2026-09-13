import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sheet_surface.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'consent_choices.dart';
import 'consent_cubit.dart';

// Presentation-only guard: two entry points never stack the same consent sheet.
final _openNavigators = <NavigatorState>{};

Future<void> showPrivacyConsentSheet(
  BuildContext context, {
  required String source,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (!_openNavigators.add(navigator)) return;
  final cubit = context.read<ConsentCubit>();
  try {
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
              child: SheetSurface(
                title: AppLocalizations.of(
                  sheetContext,
                )!.privacyOnboardingTitle,
                showClose: true,
                onClose: state.saving
                    ? null
                    : () => Navigator.maybePop(sheetContext),
                child: ConsentChoices(
                  source: source,
                  onContinue: () => Navigator.pop(sheetContext, true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (saved != true) await cubit.stopHere();
  } finally {
    _openNavigators.remove(navigator);
  }
}
