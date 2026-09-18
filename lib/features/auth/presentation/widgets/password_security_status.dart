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

/// Shared feedback with a compact line by default, or wrapping supporting
/// copy that fades into feedback when [supportingText] is provided.
class PasswordSecurityStatusLine extends StatelessWidget {
  const PasswordSecurityStatusLine({
    super.key,
    required this.password,
    required this.isAcceptable,
    required this.securityState,
    this.message,
    this.messageColor,
    this.supportingText,
  });

  final String password;
  final bool isAcceptable;
  final PasswordSecurityState securityState;

  /// Replaces the derived strength/breach status with a higher-priority form
  /// error, keeping every password state in the same fixed one-line slot.
  final String? message;
  final Color? messageColor;
  final String? supportingText;

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
      secureMessage: supportingText != null ? '' : null,
    );

    if (supportingText != null) {
      final hasFeedback = feedback.text.isNotEmpty;
      final text = hasFeedback ? feedback.text : supportingText!;
      return ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.xxxl + AppSpacing.xs,
        ),
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.center,
            children: [...previousChildren, ?currentChild],
          ),
          child: Semantics(
            key: ValueKey(text),
            liveRegion: hasFeedback,
            child: SizedBox(
              width: double.infinity,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: hasFeedback
                      ? feedback.color
                      : AppColors.onSurfaceSubtle(Theme.of(context).brightness),
                ),
              ),
            ),
          ),
        ),
      );
    }

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
