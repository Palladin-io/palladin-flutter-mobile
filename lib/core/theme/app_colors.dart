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
  static const Color brandRed = Color(0xFFFF4D5F);

  /// Teal accent — primary interactive color and loading indicators.
  static const Color tealAccent = Color(0xFF48ECDF);

  // === UI Components ===

  /// Background for disabled/secondary buttons (Apple, X).
  static const Color disabledButtonBackground = Color(0xFF1A1A1A);

  /// Google brand blue — used in the Google OAuth button icon.
  static const Color googleBlue = Color(0xFF4285F4);
}
