import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/api_key.dart';
import '../bloc/settings_cubit.dart';
import 'revoke_confirm_dialog.dart';
import 'settings_error_text.dart';

/// API-keys block of the settings screen — a section header plus the
/// list of keys (or an empty / loading / error state).
///
/// Generating a new key is owned by the screen's "Generate" button, so
/// this widget only renders the list and the per-row Revoke action.
class ApiKeyList extends StatelessWidget {
  const ApiKeyList({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.settingsApiKeys.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textTertiaryMobile,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.settingsApiKeysSubtitle,
              style: TextStyle(
                color: AppColors.onSurfaceSubtle(brightness),
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            switch (state.keysStatus) {
              SectionStatus.initial ||
              SectionStatus.loading =>
                const _KeysSkeleton(),
              SectionStatus.error => _KeysError(
                  message: settingsErrorMessage(l10n, state.keysError!),
                  onRetry: () => context.read<SettingsCubit>().loadApiKeys(),
                ),
              SectionStatus.loaded => state.apiKeys.isEmpty
                  ? const _KeysEmpty()
                  : _KeysLoaded(keys: state.apiKeys),
            },
          ],
        );
      },
    );
  }
}

class _KeysLoaded extends StatelessWidget {
  const _KeysLoaded({required this.keys});

  final List<ApiKey> keys;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final key in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ApiKeyCard(apiKey: key),
          ),
      ],
    );
  }
}

/// A single API-key row — name, masked representation, status badge,
/// created date and (for active keys) a revoke action.
class _ApiKeyCard extends StatelessWidget {
  const _ApiKeyCard({required this.apiKey});

  final ApiKey apiKey;

  Future<void> _onRevoke(BuildContext context) async {
    final confirmed = await RevokeConfirmDialog.show(context, apiKey.name);
    if (!confirmed || !context.mounted) return;
    await context.read<SettingsCubit>().revokeApiKey(apiKey.apiKeyId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.all(14),
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        apiKey.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.onSurface(brightness),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(status: apiKey.status),
                  ],
                ),
                const SizedBox(height: 4),
                // Masked representation — the real secret is never
                // available client-side after creation, so we render a
                // fixed `cv_••••••••` placeholder for visual identity.
                Text(
                  'cv_••••••••',
                  style: TextStyle(
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.settingsApiKeyCreated(_formatDate(apiKey.createdAt)),
                  style: TextStyle(
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (apiKey.isActive)
            TextButton(
              onPressed: () => _onRevoke(context),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandRed,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
              ),
              child: Text(
                l10n.settingsRevoke,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Formats a date as `YYYY-MM-DD` — locale-neutral and stable.
  String _formatDate(DateTime date) {
    final d = date.toLocal();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}

/// Status pill — teal for active, red for revoked.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ApiKeyStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isActive = status == ApiKeyStatus.active;
    final color = isActive ? AppColors.positiveAccent : AppColors.brandRed;
    final label = isActive
        ? l10n.settingsApiKeyStatusActive
        : l10n.settingsApiKeyStatusRevoked;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Empty-state for the API-keys list.
class _KeysEmpty extends StatelessWidget {
  const _KeysEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.vpn_key_outlined,
            size: 32,
            color: AppColors.onSurfaceSubtle(brightness),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.settingsApiKeysEmpty,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.settingsApiKeysEmptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton placeholder shown while the key list loads.
class _KeysSkeleton extends StatelessWidget {
  const _KeysSkeleton();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Column(
      children: List.generate(
        2,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: 78,
            decoration: BoxDecoration(
              color: AppColors.onSurface(brightness).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder(brightness)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline error card for a failed key-list load, with a retry button.
class _KeysError extends StatelessWidget {
  const _KeysError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.tealAccent,
            ),
            child: Text(l10n.settingsRetry),
          ),
        ],
      ),
    );
  }
}
