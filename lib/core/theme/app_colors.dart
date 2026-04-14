import 'package:flutter/material.dart';

/// Central color palette for Claw Vault.
///
/// All colors used across the app must reference this class.
/// Never use inline color literals outside of this file.
abstract final class AppColors {
  // === Backgrounds ===

  /// Dark theme scaffold background — deep navy.
  static const Color darkBackground = Color(0xFF000B2E);

  /// Dark theme surface — elevated navy.
  static const Color darkSurface = Color(0xFF1A2A4A);

  /// Light theme scaffold background — warm cream.
  static const Color lightBackground = Color(0xFFFDF9E4);

  /// Light theme surface — slightly darker cream.
  static const Color lightSurface = Color(0xFFEEEAD4);

  // === Brand ===

  /// Brand red — "Vault" wordmark and error states.
  static const Color brandRed = Color(0xFFFF4F4F);

  /// Teal accent — primary interactive color and loading indicators.
  static const Color tealAccent = Color(0xFF48ECDF);

  // === Text (dark mode) ===

  /// Primary text color in dark mode — warm cream (same hue as light background).
  static const Color textPrimary = Color(0xFFFDF9E4);

  /// Secondary text color in dark mode — cool blue-gray.
  static const Color textSecondary = Color(0xFFB8C5D4);

  /// Tertiary / muted text color in dark mode — darker blue-gray.
  static const Color textTertiary = Color(0xFF6B7A8E);

  // === UI Components ===

  /// Peach color for "done" progress step dots.
  static const Color doneDot = Color(0xFFFFAB87);

  /// Background for disabled/secondary buttons (Apple, X).
  static const Color disabledButtonBackground = Color(0xFF1A1A1A);

  /// Google brand blue — used in the Google OAuth button icon.
  static const Color googleBlue = Color(0xFF4285F4);

  // === Onboarding / strength indicator ===

  /// Mid-strength color for the password strength meter — amber.
  static const Color strengthFair = Color(0xFFF4B942);

  /// Positive accent used for "correct" checkmarks during recovery
  /// word confirmation. Matches the prototype's `#2EC4B6`.
  static const Color positiveAccent = Color(0xFF2EC4B6);

  /// Warning banner background used on the recovery-key backup screen.
  static const Color warningBackground = Color(0x33FF4F4F);

  // === Onboarding scaffold gradient ===
  //
  // These four stops describe the 160deg dark background gradient used
  // by the onboarding screens. Kept here so the gradient reads the same
  // as every other color in the app.
  //
  // Start of the gradient — matches [darkBackground].
  static const Color onboardingGradientStart = Color(0xFF000B2E);

  /// Second stop of the onboarding gradient — a lighter navy.
  static const Color onboardingGradientMidTop = Color(0xFF0A1A3E);

  /// Third stop of the onboarding gradient — a cooler mid-navy.
  static const Color onboardingGradientMidBottom = Color(0xFF0E1230);

  /// End of the gradient — matches [darkBackground].
  static const Color onboardingGradientEnd = Color(0xFF000B2E);
}
