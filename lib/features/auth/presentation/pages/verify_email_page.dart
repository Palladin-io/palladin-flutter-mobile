import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/auth_brand_layout.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../bloc/auth_bloc.dart';
import '../cubit/verify_email_cubit.dart';
import '../widgets/auth_brand_header.dart';
import '../widgets/oauth_button.dart';

/// Email-verification screen.
///
/// Two modes selected by [token]:
///   * `token != null` → verification-result mode (a deep link arrived);
///     the token is submitted and the outcome shown.
///   * `token == null` → the "verify your email" gate for an
///     authenticated-but-unverified account, with a throttled resend.
class VerifyEmailPage extends StatelessWidget {
  const VerifyEmailPage({super.key, this.token});

  final String? token;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VerifyEmailCubit>(
      create: (_) => getIt<VerifyEmailCubit>(),
      child: _VerifyEmailView(token: token),
    );
  }
}

class _VerifyEmailView extends StatefulWidget {
  const _VerifyEmailView({this.token});

  final String? token;

  @override
  State<_VerifyEmailView> createState() => _VerifyEmailViewState();
}

class _VerifyEmailViewState extends State<_VerifyEmailView> {
  @override
  void initState() {
    super.initState();
    final token = widget.token;
    if (token != null && token.isNotEmpty) {
      context.read<VerifyEmailCubit>().verify(token);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<VerifyEmailCubit, VerifyEmailState>(
      listenWhen: (p, c) => p.resend != c.resend || p.check != c.check,
      listener: (context, state) {
        if (state.resend == ResendStatus.sent) {
          AnalyticsService.instance.capture(
            'auth',
            'verification-email-resent',
          );
          _snack(context, AppLocalizations.of(context)!.authVerifyResendSent);
        } else if (state.resend == ResendStatus.error) {
          _snack(context, AppLocalizations.of(context)!.authVerifyResendError);
        }
        if (state.check == VerificationCheckStatus.verified) {
          context.read<AuthBloc>().add(const AuthEmailVerified());
        } else if (state.check == VerificationCheckStatus.pending) {
          _snack(context, AppLocalizations.of(context)!.authVerifyStillPending);
        } else if (state.check == VerificationCheckStatus.error) {
          _snack(context, AppLocalizations.of(context)!.authVerifyCheckError);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AuthBrandBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                0,
                AppSpacing.screenH,
                AppSpacing.xxl,
              ),
              child: AuthContentWidth(
                child: BlocBuilder<VerifyEmailCubit, VerifyEmailState>(
                  builder: (context, state) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AuthBrandHeader(),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(
                              top: AuthBrandHeader.formTopSpacing,
                            ),
                            child:
                                widget.token != null && widget.token!.isNotEmpty
                                ? _ResultBody(state: state)
                                : const _GateBody(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

/// Result mode — shows the outcome of verifying a token.
class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.state});

  final VerifyEmailState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    switch (state.verification) {
      case VerificationStatus.idle:
      case VerificationStatus.verifying:
        return Column(
          children: [
            const CircularProgressIndicator(color: AppColors.brandRed),
            const SizedBox(height: AppSpacing.section),
            Text(
              l10n.authVerifyingTitle,
              style: TextStyle(
                fontSize: 15,
                color: AppColors.onSurfaceSubtle(brightness),
              ),
            ),
          ],
        );
      case VerificationStatus.verified:
        return _StatusColumn(
          icon: Icons.check_circle_outline,
          iconColor: AppColors.positiveAccent,
          title: l10n.authVerifiedTitle,
          message: l10n.authVerifiedSubtitle,
          action: _ContinueButton(label: l10n.authVerifyContinue),
        );
      case VerificationStatus.expired:
        return _StatusColumn(
          icon: Icons.schedule,
          iconColor: AppColors.brandRed,
          title: l10n.authVerifyExpiredTitle,
          message: l10n.authVerifyExpiredSubtitle,
          action: _ResendOrLoginAction(),
        );
      case VerificationStatus.invalid:
        return _StatusColumn(
          icon: Icons.error_outline,
          iconColor: AppColors.brandRed,
          title: l10n.authVerifyInvalidTitle,
          message: l10n.authVerifyInvalidSubtitle,
          action: _ResendOrLoginAction(),
        );
      case VerificationStatus.serverError:
        return _StatusColumn(
          icon: Icons.cloud_off,
          iconColor: AppColors.brandRed,
          title: l10n.authVerifyInvalidTitle,
          message: l10n.errorConnectionFailed,
          action: _ResendOrLoginAction(),
        );
    }
  }
}

/// Gate mode — the "please verify your email" prompt with a resend.
class _GateBody extends StatelessWidget {
  const _GateBody();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authState = context.watch<AuthBloc>().state;
    final email = authState is AuthAuthenticated ? authState.email : null;

    return BlocBuilder<VerifyEmailCubit, VerifyEmailState>(
      builder: (context, state) {
        final sending = state.resend == ResendStatus.sending;
        final checking = state.check == VerificationCheckStatus.checking;
        return _StatusColumn(
          prominentMessage: true,
          message: email != null && email.isNotEmpty
              ? l10n.authVerifyGateSubtitle(email)
              : l10n.authVerifyGateSubtitleNoEmail,
          secondaryMessage: l10n.authVerifyGateInstruction,
          action: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton(
                label: l10n.authVerifyResendButton,
                isLoading: sending,
                onPressed: sending
                    ? null
                    : () => context.read<VerifyEmailCubit>().resend(),
              ),
              const SizedBox(height: AppSpacing.sm),
              OAuthButton(
                label: l10n.authVerifyCheckAgain,
                icon: checking
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.xs),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.brandRed,
                        ),
                      )
                    : const Icon(
                        Icons.mark_email_read_outlined,
                        color: AppColors.brandRed,
                        size: 20,
                      ),
                onPressed: sending || checking
                    ? null
                    : () {
                        final authState = context.read<AuthBloc>().state;
                        if (authState is! AuthAuthenticated) return;
                        context.read<VerifyEmailCubit>().checkAgain(
                          privateKey: authState.privateKey,
                          defaultVaultName: l10n.defaultVaultName,
                        );
                      },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: checking
                    ? null
                    : () => context.read<AuthBloc>().add(
                        const AuthLogoutRequested(),
                      ),
                child: Text(
                  l10n.authVerifyLogout,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Continue" after a successful verification — hands the verified state
/// to `AuthBloc` (authenticated user) or forwards to login otherwise.
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      label: label,
      onPressed: () {
        final authState = context.read<AuthBloc>().state;
        if (authState is AuthAuthenticated) {
          context.read<VerifyEmailCubit>().checkAgain(
            privateKey: authState.privateKey,
            defaultVaultName: AppLocalizations.of(context)!.defaultVaultName,
          );
        } else {
          context.go('/login');
        }
      },
    );
  }
}

/// Failure action — resend when authenticated, else go to login.
class _ResendOrLoginAction extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authState = context.watch<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      return BlocBuilder<VerifyEmailCubit, VerifyEmailState>(
        builder: (context, state) {
          final sending = state.resend == ResendStatus.sending;
          return PrimaryButton(
            label: l10n.authVerifyResendButton,
            isLoading: sending,
            onPressed: sending
                ? null
                : () => context.read<VerifyEmailCubit>().resend(),
          );
        },
      );
    }
    return PrimaryButton(
      label: l10n.authVerifyGoToLogin,
      onPressed: () => context.go('/login'),
    );
  }
}

class _StatusColumn extends StatelessWidget {
  const _StatusColumn({
    this.icon,
    this.iconColor,
    this.title,
    required this.message,
    this.secondaryMessage,
    this.prominentMessage = false,
    required this.action,
  });

  final IconData? icon;
  final Color? iconColor;
  final String? title;
  final String message;
  final String? secondaryMessage;
  final bool prominentMessage;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (icon != null) ...[
          Icon(icon, color: iconColor, size: 48),
          const SizedBox(height: AppSpacing.section),
        ],
        if (title != null) ...[
          Text(
            title!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface(brightness),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: prominentMessage ? 15 : 13,
            fontWeight: prominentMessage ? FontWeight.w600 : FontWeight.w400,
            color: prominentMessage
                ? AppColors.onSurface(brightness)
                : AppColors.onSurfaceSubtle(brightness),
            height: 1.4,
          ),
        ),
        if (secondaryMessage != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            secondaryMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.onSurfaceSubtle(brightness),
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        action,
      ],
    );
  }
}
