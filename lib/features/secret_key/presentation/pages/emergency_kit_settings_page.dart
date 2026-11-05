import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../config/env_config.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/storage/account_secret_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../unlock/data/datasources/account_remote_datasource.dart';
import '../../../unlock/data/services/identity_kdf_service.dart';
import '../../data/services/emergency_kit_pdf_service.dart';
import '../cubit/emergency_kit_settings_cubit.dart';
import '../emergency_kit_export.dart';

/// Settings → Security → Emergency Kit (re-download, CVT-717).
class EmergencyKitSettingsPage extends StatelessWidget {
  const EmergencyKitSettingsPage({super.key, this.cubitBuilder, this.export});

  /// Test seam; defaults to the DI-backed cubit for the signed-in account.
  final EmergencyKitSettingsCubit Function(String accountId)? cubitBuilder;

  /// Test seam for the PDF build + share step.
  final Future<void> Function(
    BuildContext context,
    String accountId,
    String email,
    List<int> secret,
  )?
  export;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final auth = context.watch<AuthBloc>().state;
    final unlocked = auth is AuthAuthenticated && auth.masterKey != null;

    return AppScreen.appBar(
      floatingActionButton: const FabRegistrar(fab: null),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
        title: AppBarTitle(
          title: l10n.emergencyKitSettingsTitle,
          subtitle: l10n.emergencyKitSettingsSubtitle,
        ),
      ),
      body: !unlocked
          ? _Message(text: l10n.emergencyKitSettingsLocked)
          : BlocProvider(
              create: (_) =>
                  (cubitBuilder ?? _defaultCubit)(auth.userId)..load(),
              child: _Body(accountId: auth.userId, export: export),
            ),
    );
  }

  static EmergencyKitSettingsCubit _defaultCubit(String accountId) =>
      EmergencyKitSettingsCubit(
        accountId: accountId,
        store: getIt<AccountSecretStore>(),
        loadAccount: () => getIt<AccountRemoteDatasource>().getAccount(),
        kdfService: getIt<IdentityKdfService>(),
      );
}

class _Body extends StatefulWidget {
  const _Body({required this.accountId, required this.export});

  final String accountId;
  final Future<void> Function(BuildContext, String, String, List<int>)? export;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.masterKey == null) return;
    final password = _password.text;
    _password.clear();
    await context.read<EmergencyKitSettingsCubit>().exportKit(
      password: password,
      sessionMasterKey: auth.masterKey!,
      export: (email, secret) {
        final custom = widget.export;
        if (custom != null) {
          return custom(context, widget.accountId, email, secret);
        }
        return exportEmergencyKit(
          context: context,
          service: getIt<EmergencyKitPdfService>(),
          config: getIt<EnvConfig>(),
          email: email,
          accountId: widget.accountId,
          accountSecret: secret,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return BlocConsumer<EmergencyKitSettingsCubit, EmergencyKitSettingsState>(
      listener: (context, state) {
        if (state is EmergencyKitSettingsReady &&
            (state.exported || state.exportFailed)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.exported
                    ? l10n.emergencyKitSettingsShared
                    : l10n.emergencyKitSaveFailed,
              ),
            ),
          );
        }
      },
      builder: (context, state) => switch (state) {
        EmergencyKitSettingsLoading() => const Center(
          child: CircularProgressIndicator(color: AppColors.brandRed),
        ),
        EmergencyKitSettingsMissing() => _Message(
          text: l10n.emergencyKitSettingsMissing,
        ),
        EmergencyKitSettingsLoadFailed() => _Message(
          text: l10n.emergencyKitSettingsLoadFailed,
          action: TextButton(
            onPressed: () => context.read<EmergencyKitSettingsCubit>().load(),
            child: Text(
              l10n.emergencyKitSettingsRetry,
              style: const TextStyle(color: AppColors.brandRed),
            ),
          ),
        ),
        EmergencyKitSettingsReady() => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenH,
                ),
                children: [
                  _SecretKeyCard(masked: state.maskedSecretKey),
                  const SizedBox(height: AppSpacing.section),
                  Text(
                    l10n.emergencyKitSettingsConfirmTitle,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.emergencyKitSettingsConfirmMessage,
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted(brightness),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.fieldGap),
                  OnboardingTextField(
                    key: const ValueKey('emergencyKitPassword'),
                    controller: _password,
                    label: l10n.emergencyKitSettingsPasswordLabel,
                    obscureText: true,
                    enabled: !state.busy,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _create(),
                    feedbackVisible: state.wrongPassword,
                    feedbackReserveSpace: false,
                    feedbackChild: Text(
                      l10n.emergencyKitSettingsWrongPassword,
                      style: const TextStyle(
                        color: AppColors.brandRed,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
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
                label: l10n.emergencyKitSettingsCreate,
                leading: const Icon(Icons.ios_share, size: 18),
                isLoading: state.busy,
                onPressed: _create,
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _SecretKeyCard extends StatelessWidget {
  const _SecretKeyCard({required this.masked});

  final String masked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.emergencyKitSecretKeyTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.emergencyKitSecretKeyHint,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          Row(
            children: [
              Expanded(
                child: Text(
                  masked,
                  style: TextStyle(
                    color: AppColors.onSurface(brightness),
                    fontFamily: AppFonts.monospace,
                    fontFamilyFallback: AppFonts.monospaceFallback,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                Icons.lock_outline,
                size: 16,
                color: AppColors.onSurfaceSubtle(brightness),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenH),
      child: Column(
        children: [
          Text(
            text,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}
