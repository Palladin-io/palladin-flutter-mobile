import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_toggle.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../core/widgets/sheet_action_buttons.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/user_consent.dart';
import 'consent_cubit.dart';

/// One explicit form shared by the startup sheet and Privacy settings.
class ConsentChoices extends StatelessWidget {
  const ConsentChoices({super.key, required this.source, this.onContinue});
  final String source;
  final VoidCallback? onContinue;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConsentCubit>().state;
    final identity = [
      state.userId,
      Localizations.localeOf(context).languageCode,
      ...state.consents.map((c) => c.currentNotice?.version),
    ].join(':');
    return _ConsentForm(
      key: ValueKey(identity),
      source: source,
      onContinue: onContinue,
    );
  }
}

class _ConsentForm extends StatefulWidget {
  const _ConsentForm({super.key, required this.source, this.onContinue});
  final String source;
  final VoidCallback? onContinue;
  @override
  State<_ConsentForm> createState() => _ConsentChoicesState();
}

class _ConsentChoicesState extends State<_ConsentForm> {
  final _draft = <String, bool>{};
  List<ConsentDecision> _pending = [];
  bool _saving = false;
  static const _purposes = ['product_analytics', 'email_marketing'];

  bool _selected(UserConsent consent) =>
      _draft[consent.purpose] ?? consent.granted;

  Future<void> _persist(List<ConsentDecision> decisions) async {
    final cubit = context.read<ConsentCubit>();
    setState(() {
      _saving = true;
      _pending = decisions;
    });
    for (final decision in decisions) {
      final success = await cubit.save(decision);
      if (!mounted) return;
      if (!success) {
        await cubit.stopHere();
        if (mounted) {
          setState(() {
            _saving = false;
            if (cubit.state.failedDecision == null) {
              _pending = [];
              if (cubit.state.requiresReconfirmation) _draft.clear();
            }
          });
        }
        return;
      }
      setState(() {
        _pending = _pending.skip(1).toList();
      });
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _draft.clear();
    });
    if (widget.onContinue case final next?) {
      next();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.privacySaved)),
      );
    }
  }

  Future<void> _save({
    bool acceptAll = false,
    bool activateHere = false,
  }) async {
    final cubit = context.read<ConsentCubit>();
    if (_saving ||
        cubit.state.saving ||
        cubit.state.loading ||
        cubit.state.error == ConsentErrorKind.load ||
        (acceptAll && !_hasCurrentNotices(cubit.state.consents))) {
      return;
    }
    if (acceptAll) {
      // Stop synchronously before awaiting storage. Lock the whole operation.
      setState(() {
        _saving = true;
        for (final purpose in _purposes) {
          _draft[purpose] = true;
        }
      });
      await cubit.stopHere();
      if (!mounted) return;
    }
    final decisions = <ConsentDecision>[];
    for (final purpose in _purposes) {
      final consent = cubit.state.consents
          .where((c) => c.purpose == purpose)
          .firstOrNull;
      if (consent == null) continue;
      final selected = acceptAll || _selected(consent);
      final activate = activateHere && purpose == 'product_analytics';
      if (!acceptAll &&
          !activate &&
          selected == consent.granted &&
          consent.status != 'unknown') {
        continue;
      }
      if (selected && consent.currentNotice == null) continue;
      final decision = cubit.decision(consent, selected, widget.source);
      if (decision != null) decisions.add(decision);
    }
    if (decisions.isEmpty) {
      setState(() => _saving = false);
      if (_hasCurrentNotices(cubit.state.consents)) {
        widget.onContinue?.call();
      }
      return;
    }
    // Confirm analytics grants last, including ordinary Save. Withdrawals still
    // run first; no local grant is restored during a partial-save retry.
    decisions.sort((a, b) {
      int rank(ConsentDecision d) =>
          d.purpose == 'product_analytics' && d.granted ? 1 : 0;
      return rank(a).compareTo(rank(b));
    });
    if (!acceptAll &&
        decisions.any((d) => d.purpose == 'product_analytics' && d.granted)) {
      setState(() => _saving = true);
      await cubit.stopHere();
      if (!mounted) return;
    }
    await _persist(decisions);
  }

  bool _hasCurrentNotices(List<UserConsent> consents) => _purposes.every(
    (purpose) =>
        consents.any((c) => c.purpose == purpose && c.currentNotice != null),
  );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConsentCubit>().state;
    final cubit = context.read<ConsentCubit>();
    final l10n = AppLocalizations.of(context)!;
    final busy = _saving || state.saving;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.privacySubtitle),
        const SizedBox(height: AppSpacing.section),
        _card(
          l10n.privacyEssential,
          l10n.privacyEssentialDescription,
          Text(l10n.privacyAlwaysActive, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        if (state.loading)
          const SkeletonBox(height: 180)
        else
          for (final purpose in _purposes) ...[
            Builder(
              builder: (context) {
                final consent = state.consents
                    .where((c) => c.purpose == purpose)
                    .firstOrNull;
                final analytics = purpose == 'product_analytics';
                final label = analytics
                    ? l10n.privacyAnalytics
                    : l10n.privacyMarketing;
                final value = consent == null ? false : _selected(consent);
                final enabled =
                    !busy &&
                    state.error != ConsentErrorKind.load &&
                    consent != null &&
                    (consent.currentNotice != null || value);
                void change() {
                  if (!enabled) return;
                  if (analytics && value) cubit.stopHere();
                  setState(() {
                    _draft[purpose] = !value;
                    _pending = [];
                  });
                }

                return _card(
                  label,
                  analytics
                      ? l10n.privacyAnalyticsDescription
                      : l10n.privacyMarketingDescription,
                  Semantics(
                    label: label,
                    toggled: value,
                    enabled: enabled,
                    onTap: enabled ? change : null,
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: AppSpacing.controlHeight,
                        height: AppSpacing.controlHeight,
                        child: InkWell(
                          onTap: enabled ? change : null,
                          child: Center(
                            child: IgnorePointer(
                              child: AppToggle(
                                value: value,
                                onChanged: enabled ? (_) {} : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  details: [
                    if (widget.source == 'mobile_settings' && analytics) ...[
                      Text(
                        state.locallyActive
                            ? l10n.privacyActiveHere
                            : l10n.privacyInactiveHere,
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (consent?.granted == true &&
                          value &&
                          !state.locallyActive &&
                          consent.currentNotice != null)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => _save(activateHere: true),
                          child: Text(l10n.privacyActivateHere),
                        ),
                    ],
                    if (consent?.currentNotice case final notice?)
                      Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: AppColors.transparent,
                          expansionTileTheme: ExpansionTileTheme.of(context)
                              .copyWith(
                                shape: const Border(),
                                collapsedShape: const Border(),
                              ),
                        ),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            l10n.privacyDetails,
                            style: const TextStyle(fontSize: 12),
                          ),
                          children: [Text(notice.text)],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.cardGap),
          ],
        if (!state.loading &&
            state.consents.where((c) => c.currentNotice != null).length < 2)
          Text(
            l10n.privacyNoticeUnavailable,
            style: const TextStyle(fontSize: 12),
          ),
        if (state.error != null ||
            state.requiresReconfirmation ||
            _pending.isNotEmpty && !busy) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              state.error == ConsentErrorKind.load
                  ? l10n.privacyLoadError
                  : state.requiresReconfirmation
                  ? l10n.privacyConflictError
                  : l10n.privacySaveError,
              style: const TextStyle(color: AppColors.brandRed),
            ),
          ),
          if (state.error == ConsentErrorKind.load ||
              _pending.isNotEmpty && !state.requiresReconfirmation)
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      if (state.error != ConsentErrorKind.load &&
                          _pending.isNotEmpty) {
                        _persist(_pending);
                      } else {
                        cubit.refresh();
                      }
                    },
              child: Text(l10n.privacyRetry),
            ),
        ],
      ],
    );
    final footer = SheetActionButtons(
      equalActions: true,
      busy: busy,
      cancelLabel: l10n.privacySaveChoice,
      confirmLabel: busy ? l10n.privacySaving : l10n.privacyAcceptAll,
      confirmColor: AppColors.brandRed,
      onCancel:
          state.loading ||
              state.error == ConsentErrorKind.load ||
              !state.consents.any((c) => c.currentNotice != null || c.granted)
          ? null
          : () => _save(),
      onConfirm:
          state.loading ||
              state.error == ConsentErrorKind.load ||
              !_hasCurrentNotices(state.consents)
          ? null
          : () => _save(acceptAll: true),
    );
    return PopScope(
      canPop: !busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenH),
              child: body,
            ),
          ),
          footer,
        ],
      ),
    );
  }

  Widget _card(
    String title,
    String description,
    Widget control, {
    List<Widget> details = const [],
  }) {
    final brightness = Theme.of(context).brightness;
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
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.innerGap),
              control,
            ],
          ),
          const SizedBox(height: AppSpacing.innerGap),
          Text(description),
          if (details.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.innerGap),
            ...details,
          ],
        ],
      ),
    );
  }
}
