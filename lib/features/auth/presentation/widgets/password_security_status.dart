import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/services/hibp_service.dart';

typedef PasswordBreachChecker = Future<HibpResult> Function(String password);
typedef PasswordSecurityFeedback = ({String text, Color color});

/// Resolves the shared presentation for every password-security state.
/// Screens that place the feedback elsewhere reuse this function instead of
/// duplicating checking, strength, and breach-message precedence.
PasswordSecurityFeedback resolvePasswordSecurityFeedback({
  required AppLocalizations l10n,
  required String password,
  required bool isAcceptable,
  required PasswordSecurityCheckController controller,
  String? message,
  Color? messageColor,
  String? secureMessage,
}) {
  if (message != null) {
    return (text: message, color: messageColor ?? AppColors.brandRed);
  }

  return switch ((
    password.isEmpty,
    controller.result,
    controller.isChecking,
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

/// Debounces the client-side HIBP check without storing the password as state.
class PasswordSecurityCheckController extends ChangeNotifier {
  PasswordSecurityCheckController({
    required PasswordBreachChecker check,
    this.debounce = const Duration(milliseconds: 500),
  }) : _check = check;

  final PasswordBreachChecker _check;
  final Duration debounce;

  Timer? _timer;
  var _generation = 0;
  var _disposed = false;

  HibpResult result = HibpResult.unknown;
  bool isChecking = false;

  bool get blocksSubmission => isChecking || result == HibpResult.pwned;

  void checkPassword(String password) {
    _timer?.cancel();
    final generation = ++_generation;
    result = HibpResult.unknown;

    if (password.length < 8) {
      isChecking = false;
      notifyListeners();
      return;
    }

    isChecking = true;
    notifyListeners();
    _timer = Timer(debounce, () async {
      final nextResult = await _check(password);
      if (_disposed || generation != _generation) return;
      result = nextResult;
      isChecking = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _timer?.cancel();
    super.dispose();
  }
}

/// One-line renderer for the shared password feedback presentation. Account
/// registration reuses [resolvePasswordSecurityFeedback] in its pinned copy
/// slot; onboarding and recovery render this fixed-height widget directly.
class PasswordSecurityStatusLine extends StatelessWidget {
  const PasswordSecurityStatusLine({
    super.key,
    required this.password,
    required this.isAcceptable,
    required this.controller,
    this.message,
    this.messageColor,
  });

  final String password;
  final bool isAcceptable;
  final PasswordSecurityCheckController controller;

  /// Replaces the derived strength/breach status with a higher-priority form
  /// error, keeping every password state in the same fixed one-line slot.
  final String? message;
  final Color? messageColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final feedback = resolvePasswordSecurityFeedback(
          l10n: l10n,
          password: password,
          isAcceptable: isAcceptable,
          controller: controller,
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
      },
    );
  }
}
