import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

abstract final class AppTheme {
  /// Light theme — warm cream background, navy text.
  static ThemeData light() {
    return ThemeData(
      brightness: Brightness.light,
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      scaffoldBackgroundColor: AppColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: AppColors.brandRed,
        error: AppColors.brandRed,
        surface: AppColors.lightSurface,
        onSurface: AppColors.darkBackground,
        onPrimary: AppColors.onBrandRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightSurface,
        foregroundColor: AppColors.darkBackground,
        elevation: 0,
      ),
      tabBarTheme: TabBarThemeData(overlayColor: tabOverlay(Brightness.light)),
      chipTheme: _chipTheme(Brightness.light),
      datePickerTheme: _datePickerTheme(Brightness.light),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Dark theme — deep navy background, cream text.
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brandRed,
        error: AppColors.brandRed,
        surface: AppColors.darkSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: AppColors.onBrandRed,
        elevation: 0,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brandRed,
      ),
      tabBarTheme: TabBarThemeData(overlayColor: tabOverlay(Brightness.dark)),
      chipTheme: _chipTheme(Brightness.dark),
      datePickerTheme: _datePickerTheme(Brightness.dark),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ChipThemeData _chipTheme(Brightness brightness) => ChipThemeData(
    backgroundColor: AppColors.cardFill(brightness),
    selectedColor: AppColors.cardFill(brightness),
    secondarySelectedColor: AppColors.cardFill(brightness),
    surfaceTintColor: AppColors.transparent,
    elevation: 0,
    pressElevation: 0,
    labelStyle: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: AppColors.onSurfaceMuted(brightness),
    ),
    secondaryLabelStyle: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: AppColors.onSurface(brightness),
    ),
    checkmarkColor: AppColors.onSurface(brightness),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    side: WidgetStateBorderSide.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.selected)
            ? AppColors.onSurface(brightness)
            : AppColors.cardBorder(brightness),
      ),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.xxs,
    ),
  );

  static WidgetStateProperty<Color?> tabOverlay(Brightness brightness) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return AppColors.transparent;
        if (states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.focused)) {
          return AppColors.onSurface(brightness).withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.hovered)) {
          return AppColors.onSurface(brightness).withValues(alpha: 0.04);
        }
        return AppColors.transparent;
      });

  /// Shared calendar-popup theme for [showDatePicker] (audit From/To filters,
  /// and any future date picker) so the dialog follows the app's light/dark
  /// surface with the brand-red accent — never Material's bare defaults.
  /// Colors come exclusively from [AppColors].
  static DatePickerThemeData _datePickerTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final onSurface = isDark ? AppColors.onBrandRed : AppColors.darkBackground;
    final subtle = AppColors.textTertiary;

    Color? selectedBg(Set<WidgetState> states) =>
        states.contains(WidgetState.selected) ? AppColors.brandRed : null;
    Color selectedFg(Set<WidgetState> states, Color unselected) =>
        states.contains(WidgetState.selected)
        ? AppColors.onBrandRed
        : unselected;

    return DatePickerThemeData(
      backgroundColor: surface,
      // Match the tint to the surface so M3 elevation tint can't shift it.
      surfaceTintColor: surface,
      headerBackgroundColor: AppColors.brandRed,
      headerForegroundColor: AppColors.onBrandRed,
      weekdayStyle: TextStyle(color: subtle),
      dayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => selectedFg(states, onSurface),
      ),
      dayBackgroundColor: WidgetStateProperty.resolveWith(selectedBg),
      todayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => selectedFg(states, AppColors.brandRed),
      ),
      todayBackgroundColor: WidgetStateProperty.resolveWith(selectedBg),
      todayBorder: const BorderSide(color: AppColors.brandRed),
      yearForegroundColor: WidgetStateProperty.resolveWith(
        (states) => selectedFg(states, onSurface),
      ),
      yearBackgroundColor: WidgetStateProperty.resolveWith(selectedBg),
      cancelButtonStyle: TextButton.styleFrom(foregroundColor: subtle),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: AppColors.brandRed,
      ),
    );
  }
}
