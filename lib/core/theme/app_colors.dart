import 'package:flutter/material.dart';

/// Central color palette for Palladin.
///
/// All colors used across the app must reference this class.
/// Never use inline color literals outside of this file.
abstract final class AppColors {
  static const Color transparent = Color(0x00000000);
  // === Backgrounds ===

  /// Dark theme scaffold background — deep graphite.
  static const Color darkBackground = Color(0xFF15171B);

  /// Dark theme surface — elevated graphite.
  static const Color darkSurface = Color(0xFF20242C);

  /// Mobile prototype "surface" card background — graphite,
  /// used by vault detail and list cards (matches `--surface` in the
  /// Astro prototype).
  static const Color mobileSurface = Color(0xFF23262C);

  /// Light theme scaffold background — warm cream.
  static const Color lightBackground = Color(0xFFE8EAED);

  /// Light theme surface — slightly darker cream.
  static const Color lightSurface = Color(0xFFDCDEE2);

  // === Brand ===

  /// Brand red — "Vault" wordmark and error states.
  static const Color brandRed = Color(0xFFE54645);

  /// Foreground (text/icon) color used on top of [brandRed] surfaces —
  /// e.g. the destructive "Delete" CTA, the empty-state "New vault"
  /// button. Single source of truth so all red-on-cream contrast pairs
  /// share the same value.
  static const Color onBrandRed = Color(0xFFFFFFFF);

  /// Neutral light fill for the date/time picker dial — the picker is forced
  /// onto a white surface regardless of app theme, so the dial face needs a
  /// fixed light grey (dark numbers stay readable on it).
  static const Color pickerDialFill = Color(0xFFEDEDF2);

  /// Opaque base colour for the upload-button shimmer label. The brandRed
  /// gradient is painted over it via a `ShaderMask` (`BlendMode.srcIn`),
  /// so only its alpha channel matters — it must be fully opaque white for
  /// the gradient to show through at full saturation.
  static const Color shimmerForeground = Color(0xFFFFFFFF);

  /// FAB drop-shadow color — `brandRed` at 35% alpha. Mirrors the
  /// prototype's `box-shadow: 0 3px 10px rgba(229,70,69,0.35)`. Kept
  /// as a const (instead of `brandRed.withValues(...)`) so it can be
  /// used inside `const` `BoxShadow` lists.
  static const Color fabShadow = Color(0x59E54645);

  /// FAB hairline border — `onBrandRed` at 20% alpha. Subtle white
  /// outline on the brand-red FAB that lifts it off the gradient
  /// backdrop. Kept as a const so the FAB's `BorderSide` can stay
  /// inline-const-friendly.
  static const Color fabBorder = Color(0x33FFFFFF);

  /// "Approve" green (`#2EC4B6`) — the solid teal-green used on the
  /// prototype's confirm CTAs (e.g. the dashboard "Register & Approve"
  /// button) and the agent-registration step accent. Matches the web
  /// prototype's approve token.
  static const Color approveGreen = Color(0xFF2EC4B6);

  /// Agent accent — violet (`#8B5CF6`). Tints the API-key onboarding step
  /// glyph; mirrors the web prototype's agent/key purple.
  static const Color agentPurple = Color(0xFF8B5CF6);

  /// Onboarding "active step" amber (`#F59E0B`) — border + glyph color of
  /// the currently-active checklist step (e.g. Enable notifications).
  static const Color onboardingStepAmber = Color(0xFFF59E0B);

  // === Text (dark mode) ===

  /// Primary text color in dark mode — warm cream (same hue as light background).
  static const Color textPrimary = Color(0xFFE8EAED);

  /// Secondary text color in dark mode — cool blue-gray.
  static const Color textSecondary = Color(0xFFB8C5D4);

  /// Tertiary / muted text color — `#8A95A6`, matching the web panel's
  /// `--cv-t3` token (both modes). Brighter than the old `#6B7A8E` so muted
  /// text / nav labels are legible on the dark gradient.
  static const Color textTertiary = Color(0xFF8A95A6);

  /// Mobile-prototype secondary text — warm sand (Astro `--t2`). Used
  /// for input labels and supporting copy on the vault screens.
  static const Color textSecondaryMobile = Color(0xFFB4B8C0);

  /// Mobile-prototype tertiary text — slate (Astro `--t3`). Used for
  /// meta lines, icon-buttons, and inactive controls on vault screens.
  static const Color textTertiaryMobile = Color(0xFF8A95A6);

  // === UI Components ===

  /// Peach color for "done" progress step dots.
  static const Color doneDot = Color(0xFFFFAB87);

  // === Onboarding / strength indicator ===

  /// Mid-strength color for the password strength meter — amber.
  static const Color strengthFair = Color(0xFFF4B942);

  /// Positive accent used for "correct" checkmarks during recovery
  /// word confirmation. Matches the prototype's `#10B981`.
  static const Color positiveAccent = Color(0xFF10B981);

  /// Warning banner background used on the recovery-key backup screen.
  static const Color warningBackground = Color(0x33E54645);

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

  /// Translucent graphite used as the bottom-nav background —
  /// `#212429` at 80 % opacity so the nav reads as a frosted
  /// rail above the gradient backdrop.
  static const Color bottomNavBackground = Color(0xCC212429);

  /// Hairline border on top of the bottom nav — bumped from the
  /// prototype's `rgba(232, 234, 237, 0.06)` (~6%) to ~10% so the 1-px
  /// stroke actually reads against the translucent graphite backdrop.
  static const Color bottomNavBorder = Color(0x1AE8EAED);

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
  static const Color onboardingGradientStart = Color(0xFF15171B);
  static const Color onboardingGradientMidTop = Color(0xFF212429);
  static const Color onboardingGradientMidBottom = Color(0xFF1A1D22);
  static const Color onboardingGradientEnd = Color(0xFF15171B);

  /// Assembled dark background — matches the web panel's authenticated
  /// background exactly: `linear-gradient(160deg, #15171B 0%, #212429 30%,
  /// #1A1D22 60%, #15171B 100%)` (see web `_authenticated.tsx` GRADIENTS).
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
  /// `linear-gradient(160deg, #E8EAED 0%, #EDEFF2 35%, #E8EAED 65%, #F0F2F5
  /// 100%)` (see web `_authenticated.tsx` GRADIENTS).
  static const LinearGradient lightBackgroundGradient = LinearGradient(
    begin: Alignment(-0.34, -0.94),
    end: Alignment(0.34, 0.94),
    colors: [
      Color(0xFFE8EAED),
      Color(0xFFEDEFF2),
      Color(0xFFE8EAED),
      Color(0xFFF0F2F5),
    ],
    // Mid stops pushed lower than the web (0.35/0.65) for the taller screen.
    stops: [0.0, 0.5, 0.8, 1.0],
  );

  static const Color authLightPageStart = Color(0xFFF8FAFC);
  static const Color authLightPageMid = Color(0xFFE3E7EC);
  static const Color authLightPageEdge = Color(0xFFC8CDD6);
  static const Alignment authLightPageCenter = Alignment(0.44, -1);
  static const Alignment authLightGlowCenter = Alignment(0, -0.56);

  /// Landing-page light surface: pale at the top-right origin and distinctly
  /// grey at the outer edge.
  static const RadialGradient authLightPageGradient = RadialGradient(
    center: authLightPageCenter,
    radius: 0.5,
    colors: [
      authLightPageStart,
      authLightPageMid,
      authLightPageEdge,
    ],
    stops: [0, 0.46, 1],
  );

  /// Landing-page logo light, anchored to the shield and dissolved into the
  /// grey page surface. The bright core is wider on mobile so the full shield
  /// sits inside the white part of the bloom.
  static const RadialGradient authLightLogoGlow = RadialGradient(
    center: authLightGlowCenter,
    radius: 0.5,
    colors: [
      Color(0xFAFFFFFF),
      Color(0xFAFFFFFF),
      Color(0xADFFFFFF),
      Color(0x29FFFFFF),
      Color(0x0EFFFFFF),
      transparent,
    ],
    stops: [0, 0.14, 0.30, 0.44, 0.54, 0.68],
  );

  /// Brightness-aware background gradient — picks the dark or light
  /// gradient based on the current theme.
  static LinearGradient backgroundGradient(Brightness b) =>
      b == Brightness.dark ? darkBackgroundGradient : lightBackgroundGradient;

  /// Existing dark-auth bloom retained independently from the light surface.
  static RadialGradient get darkAuthBrandGlow => RadialGradient(
    center: const Alignment(0, -0.2),
    radius: 0.85,
    colors: [
      onBrandRed.withValues(alpha: 0.1),
      transparent,
    ],
  );

  // ── Brightness-aware semantic colors ─────────────────────────────────
  //
  // Use Theme.of(context).brightness to pick the right variant.
  // Defined as static methods (not consts) because they depend on
  // the runtime brightness value.

  /// Primary text — cream in dark (`#E8EAED`), deep navy in light (`#15171B`).
  static Color onSurface(Brightness b) =>
      b == Brightness.dark ? textPrimary : darkBackground;

  /// Secondary / supporting text — `#B8C5D4` in dark, `#3D4E66` in light.
  static Color onSurfaceMuted(Brightness b) =>
      b == Brightness.dark ? textSecondary : const Color(0xFF3D4E66);

  /// Tertiary / placeholder text — `#6B7A8E` in dark, `#8A95A6` in light.
  static Color onSurfaceSubtle(Brightness b) =>
      b == Brightness.dark ? textTertiary : textTertiaryMobile;

  /// Input fill — `rgba(232, 234, 237,0.04)` in dark,
  /// `rgba(245, 247, 250,0.70)` in light. Matches the prototype's frosted
  /// input recipe.
  static Color inputFill(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x0AE8EAED)
          : const Color(0xB3F5F7FA);

  /// Input border — `rgba(232, 234, 237,0.08)` in dark,
  /// `rgba(12, 14, 18,0.08)` in light.
  static Color inputBorder(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x14E8EAED)
          : const Color(0x1415171B);

  /// Input text color — cream in dark, deep navy in light.
  static Color inputText(Brightness b) =>
      b == Brightness.dark ? textPrimary : darkBackground;

  /// Input hint / placeholder — slate (`#6B7A8E`) in dark,
  /// slate (`#8A95A6`) in light.
  static Color inputHint(Brightness b) =>
      b == Brightness.dark ? textTertiary : textTertiaryMobile;

  /// Glass card fill — `rgba(232, 234, 237,0.04)` in dark,
  /// `rgba(245, 247, 250,0.65)` in light.
  static Color cardFill(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x0AE8EAED)
          : const Color(0xA6F5F7FA);

  /// Glass card border — `rgba(232, 234, 237,0.06)` in dark,
  /// `rgba(12, 14, 18,0.06)` in light.
  static Color cardBorder(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x0FE8EAED)
          : const Color(0x0F15171B);

  /// Neutral OFF-state track for the compact [AppToggle] — a muted grey that
  /// reads clearly as "off" (not disabled) in both themes.
  static Color toggleTrackOff(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x33E8EAED)
          : const Color(0x3315171B);

  /// Footer overlay on a glass card — nearly transparent navy tint in
  /// light mode (`rgba(12, 14, 18,0.015)`) and a nearly transparent cream
  /// tint in dark mode (`rgba(232, 234, 237,0.02)`). Used to subtly set the
  /// card footer apart from the main card body without introducing a
  /// distinct surface colour.
  static Color cardFooterOverlay(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x05E8EAED)
          : const Color(0x0415171B);

  /// Bottom nav background — translucent graphite (`rgba(33,36,41,0.80)`) in
  /// dark, translucent cream (`rgba(245, 247, 250,0.75)`) in light.
  static Color navBackground(Brightness b) =>
      b == Brightness.dark
          ? bottomNavBackground
          : const Color(0xBFF5F7FA);

  /// Bottom nav top border — `rgba(232, 234, 237,0.06)` in dark,
  /// `rgba(12, 14, 18,0.06)` in light.
  static Color navBorder(Brightness b) =>
      b == Brightness.dark
          ? const Color(0x0FE8EAED)
          : const Color(0x0F15171B);

  /// Modal / drawer background — solid, non-transparent. `#23262C` in
  /// dark, `#F5F7FA` in light. Use this for bottom sheets and the
  /// settings drawer so they read as opaque surfaces above the gradient.
  static Color modalBackground(Brightness b) =>
      b == Brightness.dark ? mobileSurface : const Color(0xFFF5F7FA);

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
