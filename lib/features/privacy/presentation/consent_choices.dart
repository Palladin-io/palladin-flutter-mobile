import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_toggle.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/user_consent.dart';
import 'consent_cubit.dart';

class ConsentChoices extends StatelessWidget {
  const ConsentChoices({super.key, required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConsentCubit>().state;
    final l10n = AppLocalizations.of(context)!;
    if (state.loading) return const SkeletonBox(height: 180);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final consent in state.consents) ...[
          _ConsentCard(consent: consent, source: source),
          const SizedBox(height: AppSpacing.cardGap),
        ],
        if (state.error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              state.error == ConsentErrorKind.load
                  ? l10n.privacyLoadError
                  : state.failedDecision?.purpose == 'product_analytics'
                  ? l10n.privacySaveError
                  : l10n.privacyMarketingSaveError,
              style: const TextStyle(color: AppColors.brandRed),
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          TextButton(
            onPressed: state.saving
                ? null
                : () {
                    final cubit = context.read<ConsentCubit>();
                    if (state.failedDecision case final decision?) {
                      _save(context, decision);
                    } else {
                      cubit.refresh();
                    }
                  },
            child: Text(l10n.privacyRetry),
          ),
        ],
      ],
    );
  }
}

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.consent, required this.source});
  final UserConsent consent;
  final String source;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConsentCubit>().state;
    final cubit = context.read<ConsentCubit>();
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final analytics = consent.purpose == 'product_analytics';
    final label = analytics ? l10n.privacyAnalytics : l10n.privacyMarketing;
    final enabled =
        !state.saving && (consent.currentNotice != null || consent.granted);
    void choose(bool granted) {
      final decision = cubit.decision(consent, granted, source);
      if (decision != null) _save(context, decision);
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.navBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface(brightness),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.innerGap),
              Semantics(
                label: label,
                toggled: consent.granted,
                enabled: enabled,
                child: AppToggle(
                  value: consent.granted,
                  onChanged: enabled ? choose : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.innerGap),
          Text(consent.currentNotice?.text ?? l10n.privacyNoticeUnavailable),
          if (analytics) ...[
            const SizedBox(height: AppSpacing.innerGap),
            Text(
              l10n.privacyLocalActivation,
              style: const TextStyle(fontSize: 12),
            ),
            if (consent.granted &&
                !state.locallyActive &&
                consent.currentNotice != null)
              TextButton(
                onPressed: state.saving ? null : () => choose(true),
                child: Text(l10n.privacyActivateHere),
              ),
          ],
          const SizedBox(height: AppSpacing.innerGap),
          Semantics(
            liveRegion: true,
            child: Text(
              state.saving
                  ? l10n.privacySaving
                  : switch (consent.status) {
                      'granted' => l10n.privacyGranted,
                      'denied' => l10n.privacyDenied,
                      'withdrawn' => l10n.privacyWithdrawn,
                      _ => l10n.privacyUnknown,
                    },
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _save(BuildContext context, ConsentDecision decision) async {
  final success = await context.read<ConsentCubit>().save(decision);
  if (!context.mounted || !success) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(AppLocalizations.of(context)!.privacySaved)),
  );
}
