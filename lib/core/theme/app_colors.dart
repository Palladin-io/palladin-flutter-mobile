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

  /// Mobile prototype "surface" card background — slightly bluer navy
  /// used by vault detail and list cards (matches `--surface` in the
  /// Astro prototype).
  static const Color mobileSurface = Color(0xFF0D1B3E);

  /// Light theme scaffold background — warm cream.
  static const Color lightBackground = Color(0xFFFDF9E4);

  /// Light theme surface — slightly darker cream.
  static const Color lightSurface = Color(0xFFEEEAD4);

  // === Brand ===

  /// Brand red — "Vault" wordmark and error states.
  static const Color brandRed = Color(0xFFFF4F4F);

  /// Foreground (text/icon) color used on top of [brandRed] surfaces —
  /// e.g. the destructive "Delete" CTA, the empty-state "New vault"
  /// button. Single source of truth so all red-on-cream contrast pairs
  /// share the same value.
  static const Color onBrandRed = Color(0xFFFFFFFF);

  /// Opaque base colour for the upload-button shimmer label. The brandRed
  /// gradient is painted over it via a `ShaderMask` (`BlendMode.srcIn`),
  /// so only its alpha channel matters — it must be fully opaque white for
  /// the gradient to show through at full saturation.
  static const Color shimmerForeground = Color(0xFFFFFFFF);

  /// FAB drop-shadow color — `brandRed` at 35% alpha. Mirrors the
  /// prototype's `box-shadow: 0 3px 10px rgba(255,79,79,0.35)`. Kept
  /// as a const (instead of `brandRed.withValues(...)`) so it can be
  /// used inside `const` `BoxShadow` lists.
  static const Color fabShadow = Color(0x59FF4F4F);

  /// FAB hairline border — `onBrandRed` at 20% alpha. Subtle white
  /// outline on the brand-red FAB that lifts it off the gradient
  /// backdrop. Kept as a const so the FAB's `BorderSide` can stay
  /// inline-const-friendly.
  static const Color fabBorder = Color(0x33FFFFFF);

  /// Teal accent — primary interactive color and loading indicators.
  static const Color tealAccent = Color(0xFF48ECDF);

  // === Text (dark mode) ===

  /// Primary text color in dark mode — warm cream (same hue as light background).
  static const Color textPrimary = Color(0xFFFDF9E4);

  /// Secondary text color in dark mode — cool blue-gray.
  static const Color textSecondary = Color(0xFFB8C5D4);

  /// Tertiary / muted text color — `#8A95A6`, matching the web panel's
  /// `--cv-t3` token (both modes). Brighter than the old `#6B7A8E` so muted
  /// text / nav labels are legible on the dark gradient.
  static const Color textTertiary = Color(0xFF8A95A6);

  /// Mobile-prototype secondary text — warm sand (Astro `--t2`). Used
  /// for input labels and supporting copy on the vault screens.
  static const Color textSecondaryMobile = Color(0xFFC4BAA1);

  /// Mobile-prototype tertiary text — slate (Astro `--t3`). Used for
  /// meta lines, icon-buttons, and inactive controls on vault screens.
  static const Color textTertiaryMobile = Color(0xFF8A95A6);

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

  // === Vault palette (mobile prototype) ===
  //
  // Picker swatches and tinted icon-circle colors used across the
  // vault list, vault detail and create-vault flows. Mirror the Astro
  // prototype's palette one-to-one so the app feels identical.

  /// Vault accent — peach (FFAB87).
  static const Color vaultPeach = Color(0xFFFFAB87);

  /// Vault accent — sky blue (60A5FA).
  static const Color vaultBlue = Color(0xFF60A5FA);

  /// Vault accent — violet (A78BFA).
  static const Color vaultViolet = Color(0xFFA78BFA);

  /// Muted slate used as a neutral icon background and for inactive chips.
  static const Color vaultSlate = Color(0xFF8A95A6);

  /// Hairline divider color used between rows inside cards.
  static const Color hairline = Color(0x14FFFFFF);

  // === Bottom navigation ===

  /// Translucent navy used as the bottom-nav background — matches the
  /// prototype's `rgba(10, 26, 62, 0.8)` so the nav reads as a frosted
  /// rail above the gradient backdrop.
  static const Color bottomNavBackground = Color(0xCC0A1A3E);

  /// Hairline border on top of the bottom nav — bumped from the
  /// prototype's `rgba(253, 249, 228, 0.06)` (~6%) to ~10% so the 1-px
  /// stroke actually reads against the translucent navy backdrop.
  static const Color bottomNavBorder = Color(0x1AFDF9E4);

  // === Premium / billing ===

  /// Amber accent used for premium / upgrade gating — bursztynowy
  /// kolor "Pro" CTA na bottom sheecie. Tuned for dark mode (the app
  /// always runs `ThemeMode.dark`); the previous `#D4820A` was a
  /// light-mode value that read muddy against the navy background.
  static const Color premiumAmber = Color(0xFFF0C040);


  // === Dark background gradient ===
  //
  // 160deg gradient used as the background on every screen in dark mode.
  // Color stops kept here; use [darkBackgroundGradient] for the assembled
  // LinearGradient.
  static const Color onboardingGradientStart = Color(0xFF000B2E);
  static const Color onboardingGradientMidTop = Color(0xFF0A1A3E);
  static const Color onboardingGradientMidBottom = Color(0xFF0E1230);
  static const Color onboardingGradientEnd = Color(0xFF000B2E);

  /// Assembled dark background — matches the web panel's authenticated
  /// background exactly: `linear-gradient(160deg, #000B2E 0%, #0A1A3E 30%,
  /// #0E1230 60%, #000B2E 100%)` (see web `_authenticated.tsx` GRADIENTS).
  static const LinearGradient darkBackgroundGradient = LinearGradient(
    begin: Alignment(-0.34, -0.94),
    end: Alignment(0.34, 0.94),
    colors: [
      onboardingGradientStart,
      onboardingGradientMidTop,
      onboardingGradientMidBottom,
      onboardingGradientEnd,
    ],
    // Mid stops pushed lower than the web (0.3/0.6) so the brighter band sits
    // a bit further down on the taller mobile screen.
    stops: [0.0, 0.5, 0.8, 1.0],
  );

  // ── Light background gradient ────────────────────────────────────────
  //
  // 160deg gradient mirroring the Astro prototype's light-mode warm
  // cream/peach blend. Use [lightBackgroundGradient] directly or via
  // [backgroundGradient] for the brightness-aware helper.
  /// Assembled light-background gradient — matches the web panel exactly:
  /// `linear-gradient(160deg, #FDF9E4 0%, #FFF0E0 35%, #FDF9E4 65%, #FFF5E8
  /// 100%)` (see web `_authenticated.tsx` GRADIENTS).
  static const LinearGradient lightBackgroundGradient = LinearGradient(
    begin: Alignment(-0.34, -0.94),
    end: Alignment(0.34, 0.94),
    colors: [
      Color(0xFFFDF9E4),
      Color(0xFFFFF0E0),
      Color(0xFFFDF9E4),
      Color(0xFFFFF5E8),
    ],
    // Mid stops pushed lower than the web (0.35/0.65) for the taller screen.
    stops: [0.0, 0.5, 0.8, 1.0],
  );

  /// Brightness-aware background gradient — picks the dark or light
  /// gradient based on the current theme.
  static LinearGradient backgroundGradient(Brightness b) =>
      b == Brightness.dark ? darkBackgroundGradient : lightBackgroundGradient;

  // ── Brightness-aware semantic colors ─────────────────────────────────
  //
  // Use Theme.of(context).brightness to pick the right variant.
  // Defined as static methods (not consts) because they depend on
  // the runtime brightness value.

  /// Primary text — cream in dark (`#FDF9E4`), deep navy in light (`#000B2E`).
  static Color onSurface(Brightness b) =>
      b == Brightness.dark ? textPrimary : darkBackground;

  /// Secondary / supporting text — `#B8C5D4` in dark, `#3D4E66` in light.
  static Color onSurfaceMuted(Brightness b) =>
      b == Brightness.dark ? textSecondary : const Color(0xFF3D4E66);

  /// Tertiary / placeholder text — `#6B7A8E` in dark, `#8A95A6` in light.
  static Color onSurfaceSubtle(Brightness b) =>
      b == Brightness.dark ? textTertiary : textTertiaryMobile;

  /// Input fill — `rgba(253,249,228,0.04)` in dark,
  /// `rgba(255,252,247,0.70)` in light. Matches the prototype's frosted
  /// input recipe.
  static Color inputFill(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x0AFDF9E4)
          : const Color(0xB3FFFCF7);

  /// Input border — `rgba(253,249,228,0.08)` in dark,
  /// `rgba(0,11,46,0.08)` in light.
  static Color inputBorder(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x14FDF9E4)
          : const Color(0x14000B2E);

  /// Input text color — cream in dark, deep navy in light.
  static Color inputText(Brightness b) =>
      b == Brightness.dark ? textPrimary : darkBackground;

  /// Input hint / placeholder — slate (`#6B7A8E`) in dark,
  /// slate (`#8A95A6`) in light.
  static Color inputHint(Brightness b) =>
      b == Brightness.dark ? textTertiary : textTertiaryMobile;

  /// Glass card fill — `rgba(253,249,228,0.04)` in dark,
  /// `rgba(255,252,247,0.65)` in light.
  static Color cardFill(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x0AFDF9E4)
          : const Color(0xA6FFFCF7);

  /// Glass card border — `rgba(253,249,228,0.06)` in dark,
  /// `rgba(0,11,46,0.06)` in light.
  static Color cardBorder(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x0FFDF9E4)
          : const Color(0x0F000B2E);

  /// Neutral OFF-state track for the compact [AppToggle] — a muted grey that
  /// reads clearly as "off" (not disabled) in both themes.
  static Color toggleTrackOff(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x33FDF9E4)
          : const Color(0x33000B2E);

  /// Footer overlay on a glass card — nearly transparent navy tint in
  /// light mode (`rgba(0,11,46,0.015)`) and a nearly transparent cream
  /// tint in dark mode (`rgba(253,249,228,0.02)`). Used to subtly set the
  /// card footer apart from the main card body without introducing a
  /// distinct surface colour.
  static Color cardFooterOverlay(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x05FDF9E4)
          : const Color(0x04000B2E);

  /// Bottom nav background — translucent navy (`rgba(10,26,62,0.80)`) in
  /// dark, translucent cream (`rgba(255,252,247,0.75)`) in light.
  static Color navBackground(Brightness b) =>
      b == Brightness.dark
          ? bottomNavBackground
          : const Color(0xBFFFFCF7);

  /// Bottom nav top border — `rgba(253,249,228,0.06)` in dark,
  /// `rgba(0,11,46,0.06)` in light.
  static Color navBorder(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x0FFDF9E4)
          : const Color(0x0F000B2E);

  /// Modal / drawer background — solid, non-transparent. `#0D1B3E` in
  /// dark, `#FFFCF7` in light. Use this for bottom sheets and the
  /// settings drawer so they read as opaque surfaces above the gradient.
  static Color modalBackground(Brightness b) =>
      b == Brightness.dark ? mobileSurface : const Color(0xFFFFFCF7);

  /// Card / elevated surface — kept for back-compat with code paths that
  /// expect a fully opaque tile (refresh indicators, dropdown menus).
  /// New surfaces should prefer [cardFill] + [cardBorder] for the glass
  /// recipe, or [modalBackground] for solid sheets/drawers.
  static Color cardSurface(Brightness b) =>
      b == Brightness.dark ? mobileSurface : lightSurface;

  /// Premium / billing accent — `#F0C040` in dark, `#D4820A` in light.
  /// Mirrors the prototype's `--cv-premium-amber` token across themes.
  static Color premium(Brightness b) =>
      b == Brightness.dark ? premiumAmber : const Color(0xFFD4820A);

  /// Icon in default (non-interactive) state.
  static Color iconDefault(Brightness b) =>
      b == Brightness.dark ? textSecondary : const Color(0xFF5A6478);

  /// Drop-shadow tint for floating overlays (autocomplete dropdowns,
  /// popovers). Slightly stronger in dark mode where the overlay sits on
  /// a darker backdrop and needs more separation. Black at 30% (dark) /
  /// 15% (light) keeps the lift subtle without a hard edge.
  static Color dropdownShadow(Brightness b) => b == Brightness.dark
      ? const Color(0x4D000000)
      : const Color(0x26000000);
}
