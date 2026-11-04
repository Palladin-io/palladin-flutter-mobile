import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/compact_primary_button.dart';
import '../../../../core/widgets/setup_card.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/autofill_cache_service.dart';
import '../../domain/autofill_preparation.dart';

/// Cache preparation is independent from selecting Palladin in system settings.
class AutoFillPreparationCard extends StatelessWidget {
  const AutoFillPreparationCard({super.key, this.hideWhenReady = false});
  final bool hideWhenReady;

  @override
  Widget build(BuildContext context) {
    final service = context.read<AutoFillCacheService?>();
    if (service == null) return const SizedBox.shrink();
    return ValueListenableBuilder<AutoFillPreparation>(
      valueListenable: service.preparation,
      builder: (context, state, _) {
        if (hideWhenReady &&
            (state.phase == AutoFillPreparationPhase.ready ||
                state.phase == AutoFillPreparationPhase.unknown)) {
          return const SizedBox.shrink();
        }
        final l10n = AppLocalizations.of(context)!;
        final total = state.total;
        final message = switch (state.phase) {
          AutoFillPreparationPhase.unknown => l10n.autofillPreparationUnknown,
          AutoFillPreparationPhase.preparing =>
            total == null
                ? l10n.autofillPreparationWaiting
                : l10n.autofillPreparationProgress(state.examined, total),
          AutoFillPreparationPhase.publishing =>
            l10n.autofillPreparationPublishing,
          AutoFillPreparationPhase.ready => l10n.autofillPreparationReady,
          AutoFillPreparationPhase.empty => l10n.autofillPreparationEmpty,
          AutoFillPreparationPhase.failed => l10n.autofillPreparationFailed,
        };
        final busy =
            state.phase == AutoFillPreparationPhase.preparing ||
            state.phase == AutoFillPreparationPhase.publishing;
        return SetupCard(
          title: l10n.autofillPreparationTitle,
          descriptions: [message],
          actions: [
            if (busy)
              LinearProgressIndicator(
                color: AppColors.brandRed,
                backgroundColor: AppColors.textTertiary.withValues(alpha: 0.15),
                value:
                    state.phase == AutoFillPreparationPhase.preparing &&
                        total != null &&
                        total > 0
                    ? state.examined / total
                    : null,
                semanticsLabel: message,
              ),
            if (state.phase == AutoFillPreparationPhase.failed)
              CompactPrimaryButton(
                label: l10n.settingsRetry,
                onPressed: service.retryPreparation,
              ),
          ],
        );
      },
    );
  }
}
