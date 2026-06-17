import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toggle.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/notification_preference.dart';
import '../cubit/notification_preferences_cubit.dart';
import '../widgets/notification_format.dart';

/// LinkedIn-style notification settings: one row per notification type with
/// three channel toggles (Inbox / Live / Push). Mandatory types lock the
/// inbox + realtime toggles on; only push stays mutable.
class NotificationPreferencesPage extends StatelessWidget {
  const NotificationPreferencesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NotificationPreferencesCubit>(
      create: (_) => getIt<NotificationPreferencesCubit>()..load(),
      child: const _PreferencesView(),
    );
  }
}

class _PreferencesView extends StatelessWidget {
  const _PreferencesView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient(brightness),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: false,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          titleSpacing: 0,
          iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
          title: Text(
            l10n.notifPrefsTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: BlocConsumer<NotificationPreferencesCubit,
              NotificationPreferencesState>(
            listenWhen: (p, c) => p.error != c.error && c.error != null,
            listener: (context, state) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.notifPrefsSaveError)),
              );
              context.read<NotificationPreferencesCubit>().acknowledgeError();
            },
            builder: (context, state) => switch (state.status) {
              NotificationPreferencesStatus.initial ||
              NotificationPreferencesStatus.loading => const _Skeleton(),
              NotificationPreferencesStatus.error => _ErrorView(
                  message: notificationErrorMessage(l10n, state.error!),
                  onRetry: () =>
                      context.read<NotificationPreferencesCubit>().load(),
                ),
              NotificationPreferencesStatus.loaded => _Content(state: state),
            },
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.state});

  final NotificationPreferencesState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (state.items.isEmpty) {
      return Center(
        child: Text(
          l10n.notifPrefsEmpty,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(Theme.of(context).brightness),
          ),
        ),
      );
    }
    final brightness = Theme.of(context).brightness;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(
          l10n.notifPrefsHint,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        const _ChannelLegend(),
        const SizedBox(height: 10),
        for (final pref in state.items)
          _PreferenceRow(
            pref: pref,
            savingKeys: state.savingKeys,
          ),
      ],
    );
  }
}

class _ChannelLegend extends StatelessWidget {
  const _ChannelLegend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    TextStyle style() => TextStyle(
      color: AppColors.onSurfaceSubtle(brightness),
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    // Right padding (6) matches the preference row's right padding so the
    // three legend columns sit exactly above the three toggle columns.
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(width: 56, child: Text(l10n.notifPrefsChannelInbox,
              textAlign: TextAlign.center, style: style())),
          SizedBox(width: 56, child: Text(l10n.notifPrefsChannelRealtime,
              textAlign: TextAlign.center, style: style())),
          SizedBox(width: 56, child: Text(l10n.notifPrefsChannelPush,
              textAlign: TextAlign.center, style: style())),
        ],
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.pref, required this.savingKeys});

  final NotificationPreference pref;
  final Set<String> savingKeys;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _typeLabel(context, pref.type),
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (pref.mandatory) ...[
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context)!.notifPrefsMandatory,
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _ChannelToggle(
            pref: pref,
            channel: NotificationChannel.inbox,
            value: pref.inboxEnabled,
            locked: pref.mandatory,
            savingKeys: savingKeys,
          ),
          _ChannelToggle(
            pref: pref,
            channel: NotificationChannel.realtime,
            value: pref.signalREnabled,
            locked: pref.mandatory,
            savingKeys: savingKeys,
          ),
          _ChannelToggle(
            pref: pref,
            channel: NotificationChannel.push,
            value: pref.pushEnabled,
            locked: false,
            savingKeys: savingKeys,
          ),
        ],
      ),
    );
  }

  String _typeLabel(BuildContext context, String type) {
    final l10n = AppLocalizations.of(context)!;
    return switch (type) {
      'agent_pending' => l10n.notifPrefsTypeAgentPending,
      'grant_pending' => l10n.notifPrefsTypeGrantPending,
      'grant_revoked' => l10n.notifPrefsTypeGrantRevoked,
      'grant_approved' => l10n.notifPrefsTypeGrantApproved,
      'grant_denied' => l10n.notifPrefsTypeGrantDenied,
      'credential_stale' => l10n.notifPrefsTypeCredentialStale,
      _ => type
          .replaceAll(RegExp(r'[_-]+'), ' ')
          .split(' ')
          .where((p) => p.isNotEmpty)
          .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
          .join(' '),
    };
  }
}

class _ChannelToggle extends StatelessWidget {
  const _ChannelToggle({
    required this.pref,
    required this.channel,
    required this.value,
    required this.locked,
    required this.savingKeys,
  });

  final NotificationPreference pref;
  final NotificationChannel channel;
  final bool value;
  final bool locked;
  final Set<String> savingKeys;

  @override
  Widget build(BuildContext context) {
    final saving = savingKeys.contains('${pref.type}:${channel.name}');
    return SizedBox(
      width: 56,
      child: Center(
        child: saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brandRed,
                ),
              )
            : AppToggle(
                value: value,
                onChanged: locked
                    ? null
                    : (next) => context
                        .read<NotificationPreferencesCubit>()
                        .toggle(type: pref.type, channel: channel, value: next),
              ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SkeletonBox(height: 64, delay: Duration(milliseconds: i * 80)),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.tealAccent,
              ),
              child: Text(l10n.approvalRetry),
            ),
          ],
        ),
      ),
    );
  }
}
