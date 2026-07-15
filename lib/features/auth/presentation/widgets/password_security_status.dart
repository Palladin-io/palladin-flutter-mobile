import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/services/hibp_service.dart';
import '../cubit/password_security_cubit.dart';

typedef PasswordSecurityFeedback = ({String text, Color color});

/// Resolves the shared presentation for every password-security state.
/// Screens that place the feedback elsewhere reuse this function instead of
/// duplicating checking, strength, and breach-message precedence.
PasswordSecurityFeedback resolvePasswordSecurityFeedback({
  required AppLocalizations l10n,
  required String password,
  required bool isAcceptable,
  required PasswordSecurityState securityState,
  String? message,
  Color? messageColor,
  String? secureMessage,
}) {
  if (message != null) {
    return (text: message, color: messageColor ?? AppColors.brandRed);
  }

  return switch ((
    password.isEmpty,
    securityState.result,
    securityState.isChecking,
    isAcceptable,
  )) {
    (true, _, _, _) => (text: '', color: AppColors.textTertiary),
    (_, HibpResult.pwned, _, _) => (
      text: l10n.authPasswordBreached,
      color: AppColors.brandRed,
    ),
    (_, _, true, _) => (
      text: l10n.authPasswordChecking,
      color: AppColors.textTertiary,
    ),
    (_, _, _, false) => (
      text: l10n.authPasswordImprove,
      color: AppColors.strengthFair,
    ),
    (_, HibpResult.notFound, false, true) => (
      text: secureMessage ?? l10n.authPasswordSecure,
      color: AppColors.positiveAccent,
    ),
    _ => (
      text: l10n.authPasswordCheckUnavailable,
      color: AppColors.textTertiary,
    ),
  };
}

/// One-line renderer for the shared password feedback presentation. Account
/// registration reuses [resolvePasswordSecurityFeedback] in its pinned copy
/// slot; onboarding and recovery render this fixed-height widget directly.
class PasswordSecurityStatusLine extends StatelessWidget {
  const PasswordSecurityStatusLine({
    super.key,
    required this.password,
    required this.isAcceptable,
    required this.securityState,
    this.message,
    this.messageColor,
  });

  final String password;
  final bool isAcceptable;
  final PasswordSecurityState securityState;

  /// Replaces the derived strength/breach status with a higher-priority form
  /// error, keeping every password state in the same fixed one-line slot.
  final String? message;
  final Color? messageColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final feedback = resolvePasswordSecurityFeedback(
      l10n: l10n,
      password: password,
      isAcceptable: isAcceptable,
      securityState: securityState,
      message: message,
      messageColor: messageColor,
    );

    return SizedBox(
      height: AppSpacing.xxl,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Align(
          key: ValueKey(feedback.text),
          alignment: Alignment.center,
          child: Text(
            feedback.text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: feedback.color,
            ),
          ),
        ),
      ),
    );
  }
}
