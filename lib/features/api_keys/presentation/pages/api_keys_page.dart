import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../settings/domain/entities/api_key.dart';
import '../../../settings/presentation/widgets/settings_error_text.dart';
import '../bloc/api_keys_cubit.dart';
import '../widgets/api_key_card.dart';
import '../widgets/generate_api_key_sheet.dart';

/// Standalone API-keys screen — the list of every API key for the
/// organization.
///
/// Reached from the settings drawer's "API keys" item. Owns a fresh
/// [ApiKeysCubit] which loads the list on mount. Tapping a key navigates
/// to [ApiKeyDetailPage]; the "Generate" FAB opens the create sheet.
class ApiKeysPage extends StatelessWidget {
  const ApiKeysPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ApiKeysCubit>(
      create: (_) => getIt<ApiKeysCubit>()..load(),
      child: const _ApiKeysView(),
    );
  }
}

class _ApiKeysView extends StatefulWidget {
  const _ApiKeysView();

  @override
  State<_ApiKeysView> createState() => _ApiKeysViewState();
}

class _ApiKeysViewState extends State<_ApiKeysView> {
  /// Cached FAB widget — reused across rebuilds so [FabRegistrar] does
  /// not see a new object each build and re-register in a loop.
  Widget? _cachedFab;

  Future<void> _onGenerate(BuildContext context) async {
    await GenerateApiKeySheet.show(context);
  }

  /// Opens the detail screen for [keyId]. The detail page owns its own
  /// cubit, so on return we reload the list to pick up a revoke that may
  /// have happened there.
  Future<void> _onOpenKey(BuildContext context, String keyId) async {
    final cubit = context.read<ApiKeysCubit>();
    await context.push('/api-keys/$keyId');
    if (context.mounted) {
      // No need to restore the FAB: the detail page's FabRegistrar owns
      // its own stack entry and removes it on dispose, so this list's
      // entry (still on the stack underneath) resurfaces automatically.
      await cubit.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final authState = context.watch<AuthBloc>().state;
    final permissions = authState is AuthAuthenticated
        ? authState.permissions
        : 0;
    final canWrite = (permissions & Permissions.writeApiKey) != 0;

    // Cache the FAB so FabRegistrar.didUpdateWidget doesn't re-register
    // on every rebuild.
    final fab = canWrite
        ? (_cachedFab ??= Padding(
            padding: const EdgeInsets.only(
              bottom: AppSpacing.innerGap,
              right: AppSpacing.xs,
            ),
            child: AppFab(
              onPressed: () => _onGenerate(context),
              tooltip: l10n.apiKeysGenerate,
            ),
          ))
        : null;
    if (!canWrite) _cachedFab = null;

    // Title→content gap (headerGap) is owned by AppScreen.appBar.
    return AppScreen.appBar(
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleSpacing: 0,
        iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
        title: BlocBuilder<ApiKeysCubit, ApiKeysState>(
          builder: (context, state) {
            final brightness = Theme.of(context).brightness;
            final total = state.apiKeys.length;
            final active = state.apiKeys.where((k) => k.isActive).length;
            final showSummary =
                state.status == ApiKeysStatus.loaded && total > 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.apiKeysScreenTitle,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (showSummary)
                  Text(
                    l10n.apiKeysListSummary(total, active),
                    style: TextStyle(
                      color: AppColors.onSurfaceSubtle(brightness),
                      fontSize: 11,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      body: Stack(
        children: [
          BlocBuilder<ApiKeysCubit, ApiKeysState>(
            builder: (context, state) {
              return RefreshIndicator(
                color: AppColors.brandRed,
                backgroundColor: AppColors.cardSurface(brightness),
                onRefresh: () => context.read<ApiKeysCubit>().load(),
                child: _Body(
                  state: state,
                  onOpenKey: (keyId) => _onOpenKey(context, keyId),
                ),
              );
            },
          ),
          // Always mount the registrar — even without write access — so
          // this page deterministically claims the shell FAB. When the
          // user can't generate keys we register `null`, which suppresses
          // any FAB leaking from the page we were pushed over (e.g. a
          // vault detail's "add entry").
          Positioned(width: 0, height: 0, child: FabRegistrar(fab: fab)),
        ],
      ),
    );
  }
}

/// Switches between the loading / error / empty / loaded states of the
/// API-keys list. Always scrollable so [RefreshIndicator] works even on
/// the empty and error states.
class _Body extends StatelessWidget {
  const _Body({required this.state, required this.onOpenKey});

  final ApiKeysState state;
  final ValueChanged<String> onOpenKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return switch (state.status) {
      ApiKeysStatus.initial || ApiKeysStatus.loading => const _KeysSkeleton(),
      ApiKeysStatus.error => _KeysError(
        message: settingsErrorMessage(l10n, state.error!),
        onRetry: () => context.read<ApiKeysCubit>().load(),
      ),
      ApiKeysStatus.loaded =>
        state.apiKeys.isEmpty
            ? const _KeysEmpty()
            : _KeysList(keys: state.apiKeys, onOpenKey: onOpenKey),
    };
  }
}

class _KeysList extends StatelessWidget {
  const _KeysList({required this.keys, required this.onOpenKey});

  final List<ApiKey> keys;
  final ValueChanged<String> onOpenKey;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      // Title→list gap (headerGap) is owned by AppScreen.appBar.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.listBottom,
      ),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
          child: ApiKeyCard(apiKey: key, onTap: () => onOpenKey(key.apiKeyId)),
        );
      },
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Title→empty-state gap (headerGap) is owned by AppScreen.appBar.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: AppSpacing.xxl,
          ),
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
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.apiKeysEmpty,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.apiKeysEmptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onSurfaceSubtle(brightness),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Animated skeleton placeholder shown while the key list loads.
///
/// Rows are staggered by `i * 80 ms` so they do not pulse in lockstep,
/// matching the project-wide skeleton pattern.
class _KeysSkeleton extends StatelessWidget {
  const _KeysSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Title→skeleton gap (headerGap) is owned by AppScreen.appBar.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
          child: SkeletonBox(height: 78, delay: Duration(milliseconds: i * 80)),
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Title→error card gap (headerGap) is owned by AppScreen.appBar.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
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
              const SizedBox(height: AppSpacing.innerGap),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealAccent,
                ),
                child: Text(l10n.apiKeysRetry),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
