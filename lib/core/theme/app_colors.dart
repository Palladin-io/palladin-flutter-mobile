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

  /// Muted icon color — white at 60% opacity (visibility toggles, decorative icons on dark background).
  static const Color iconMuted = Color(0x99FFFFFF);

  /// Hint / placeholder text — white at 30% opacity.
  static const Color textHint = Color(0x4DFFFFFF);

  /// Faint index labels — white at 45% opacity (mnemonic word numbers).
  static const Color textHintFaint = Color(0x73FFFFFF);

  /// Secondary button border — white at 12% opacity.
  static const Color buttonBorder = Color(0x1FFFFFFF);

  // === Dark background gradient ===
  //
  // 160deg gradient used as the background on every screen in dark mode.
  // Color stops kept here; use [darkBackgroundGradient] for the assembled
  // LinearGradient.
  static const Color onboardingGradientStart = Color(0xFF000B2E);
  static const Color onboardingGradientMidTop = Color(0xFF0A1A3E);
  static const Color onboardingGradientMidBottom = Color(0xFF0E1230);
  static const Color onboardingGradientEnd = Color(0xFF000B2E);

  /// Assembled dark-background gradient — apply via
  /// `BoxDecoration(gradient: AppColors.darkBackgroundGradient)`.
  static const LinearGradient darkBackgroundGradient = LinearGradient(
    begin: Alignment(-0.34, -0.94),
    end: Alignment(0.34, 0.94),
    colors: [
      onboardingGradientStart,
      onboardingGradientMidTop,
      onboardingGradientMidBottom,
      onboardingGradientEnd,
    ],
    stops: [0.0, 0.3, 0.6, 1.0],
  );
}
