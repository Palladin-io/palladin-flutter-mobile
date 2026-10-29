import '../../../unlock/presentation/widgets/biometric_setup_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../autofill/presentation/widgets/autofill_setup_card.dart';
import '../../../unlock/data/datasources/account_remote_datasource.dart';
import '../../../unlock/data/models/account_response.dart';

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key, this.loadAccount});

  /// Account source for the TOTP visibility check; defaults to
  /// `GET /api/account`.
  final Future<AccountResponse> Function()? loadAccount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final auth = context.watch<AuthBloc>().state;
    final isPasswordAccount =
        auth is AuthAuthenticated && auth.isPasswordAccount;

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
          title: l10n.settingsSecurityTitle,
          subtitle: l10n.settingsSecuritySubtitle,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          0,
          AppSpacing.screenH,
          AppSpacing.screenBottom,
        ),
        children: [
          const BiometricSetupCard(),
          const AutoFillSetupCard(),
          _SecurityAction(
            icon: Icons.key_outlined,
            title: l10n.generatedPasswordTitle,
            subtitle: l10n.generatedPasswordSubtitle,
            onTap: () => context.push(AppRoutes.generatedPasswords),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          if (isPasswordAccount) ...[
            _SecurityAction(
              icon: Icons.password_outlined,
              title: l10n.settingsChangePassword,
              subtitle: l10n.settingsSecurityPasswordHint,
              onTap: () => context.push(AppRoutes.changePassword),
            ),
            const SizedBox(height: AppSpacing.cardGap),
          ],
          _TwoFactorAction(
            loadAccount:
                loadAccount ??
                () => getIt<AccountRemoteDatasource>().getAccount(),
            fallback: isPasswordAccount
                ? null
                : _InfoCard(
                    icon: Icons.verified_user_outlined,
                    message: l10n.settingsSecurityOAuth,
                  ),
          ),
        ],
      ),
    );
  }
}

/// TOTP protects the password login credential, so the entry is shown only
/// when Identity reports one (`kdf.credentialRevision > 0`), as on the web.
class _TwoFactorAction extends StatefulWidget {
  const _TwoFactorAction({required this.loadAccount, this.fallback});

  final Future<AccountResponse> Function() loadAccount;

  /// Shown instead when the account has no password login credential.
  final Widget? fallback;

  @override
  State<_TwoFactorAction> createState() => _TwoFactorActionState();
}

class _TwoFactorActionState extends State<_TwoFactorAction> {
  late final Future<bool> _hasPasswordCredential = _load();

  Future<bool> _load() async {
    final kdf = (await widget.loadAccount()).kdf;
    return kdf != null && kdf.credentialRevision > 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<bool>(
      future: _hasPasswordCredential,
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return _SecurityAction(
            icon: Icons.shield_outlined,
            title: l10n.settingsTwoFactor,
            subtitle: l10n.settingsSecurityTwoFactorHint,
            onTap: () => context.push(AppRoutes.totpEnroll),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return widget.fallback ?? const SizedBox.shrink();
      },
    );
  }
}

class _SecurityAction extends StatelessWidget {
  const _SecurityAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.cardFill(brightness),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder(brightness)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.brandRed, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted(brightness),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right,
              color: AppColors.onSurfaceSubtle(brightness),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardFill(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(brightness)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.vaultBlue, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.onSurfaceMuted(brightness),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
