import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../settings/domain/entities/api_key.dart';
import '../../../settings/presentation/widgets/settings_error_text.dart';
import '../bloc/api_keys_cubit.dart';
import '../widgets/api_key_details_tab.dart';
import '../widgets/revoke_api_key_dialog.dart';

/// Standalone API-key detail screen — wraps a [DefaultTabController]
/// with two tabs: "Details" and "Agents".
///
/// Owns its own [ApiKeysCubit], loads the key list on mount and resolves
/// the requested key by [keyId] from that list. The Agents tab is a
/// placeholder until the agents-per-key feature ships.
class ApiKeyDetailPage extends StatelessWidget {
  const ApiKeyDetailPage({super.key, required this.keyId});

  /// Server-issued id of the key to display.
  final String keyId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ApiKeysCubit>(
      create: (_) => getIt<ApiKeysCubit>()..load(),
      child: _ApiKeyDetailView(keyId: keyId),
    );
  }
}

class _ApiKeyDetailView extends StatelessWidget {
  const _ApiKeyDetailView({required this.keyId});

  final String keyId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient(brightness),
      ),
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            centerTitle: false,
            iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => context.pop(),
            ),
            title: _AppBarTitle(keyId: keyId),
            bottom: TabBar(
              labelColor: AppColors.brandRed,
              unselectedLabelColor: AppColors.onSurfaceSubtle(brightness),
              indicatorColor: AppColors.brandRed,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorWeight: 2,
              dividerColor: AppColors.navBorder(brightness),
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                Tab(text: l10n.apiKeysTabDetails),
                Tab(text: l10n.apiKeysTabAgents),
              ],
            ),
          ),
          body: SafeArea(
            top: false,
            child: Stack(
              children: [
                BlocBuilder<ApiKeysCubit, ApiKeysState>(
                  builder: (context, state) {
                    return TabBarView(
                      children: [
                        _DetailsTabBody(keyId: keyId, state: state),
                        const _AgentsPlaceholderTab(),
                      ],
                    );
                  },
                ),
                // Suppress any shell FAB on this screen.
                const Positioned(
                  width: 0,
                  height: 0,
                  child: FabRegistrar(fab: null),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Resolves the key name for the AppBar title, falling back to the
/// generic screen title while the list is still loading.
class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.keyId});

  final String keyId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final key = context.select<ApiKeysCubit, ApiKey?>(
      (cubit) => cubit.state.keyById(keyId),
    );
    return Text(
      key?.name ?? l10n.apiKeysDetailTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: AppColors.onSurface(brightness),
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Body of the "Details" tab — switches between loading / error /
/// not-found / loaded states resolved from the [ApiKeysCubit].
class _DetailsTabBody extends StatelessWidget {
  const _DetailsTabBody({required this.keyId, required this.state});

  final String keyId;
  final ApiKeysState state;

  Future<void> _onRevoke(BuildContext context, ApiKey key) async {
    final confirmed = await RevokeApiKeyDialog.show(context, key.name);
    if (!confirmed || !context.mounted) return;
    await context.read<ApiKeysCubit>().revokeApiKey(key.apiKeyId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    switch (state.status) {
      case ApiKeysStatus.initial:
      case ApiKeysStatus.loading:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.brandRed),
        );
      case ApiKeysStatus.error:
        return _CenteredMessage(
          message: settingsErrorMessage(l10n, state.error!),
          onRetry: () => context.read<ApiKeysCubit>().load(),
        );
      case ApiKeysStatus.loaded:
        final key = state.keyById(keyId);
        if (key == null) {
          return _CenteredMessage(message: l10n.apiKeysDetailNotFound);
        }
        return ApiKeyDetailsTab(
          apiKey: key,
          isRevoking: state.revokingKeyId == key.apiKeyId,
          onRevoke: () => _onRevoke(context, key),
        );
    }
  }
}

/// Placeholder body for the "Agents" tab — the agents-per-key feature
/// ships in a later ticket.
class _AgentsPlaceholderTab extends StatelessWidget {
  const _AgentsPlaceholderTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.smart_toy_outlined,
              size: 36,
              color: AppColors.textTertiaryMobile,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.placeholderComingSoon,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textTertiaryMobile,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered message used for the error and not-found states, with an
/// optional retry affordance.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealAccent,
                ),
                child: Text(l10n.apiKeysRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
