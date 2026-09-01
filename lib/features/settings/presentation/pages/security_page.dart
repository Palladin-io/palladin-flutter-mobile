import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/fab_registrar.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

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
          if (isPasswordAccount) ...[
            _SecurityAction(
              icon: Icons.password_outlined,
              title: l10n.settingsChangePassword,
              subtitle: l10n.settingsSecurityPasswordHint,
              onTap: () => context.push(AppRoutes.changePassword),
            ),
            const SizedBox(height: AppSpacing.cardGap),
            _SecurityAction(
              icon: Icons.shield_outlined,
              title: l10n.settingsTwoFactor,
              subtitle: l10n.settingsSecurityTwoFactorHint,
              onTap: () => context.push(AppRoutes.totpEnroll),
            ),
          ] else
            _InfoCard(
              icon: Icons.verified_user_outlined,
              message: l10n.settingsSecurityOAuth,
            ),
        ],
      ),
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
