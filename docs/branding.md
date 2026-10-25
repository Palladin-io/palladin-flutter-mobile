# Branding and neutral builds

Palladin source code is available under Apache License 2.0, while the names,
logos, launcher icons, and store artwork listed in [`../TRADEMARKS.md`](../TRADEMARKS.md)
are reserved.

The committed brand assets keep official builds reproducible. They are not
needed to modify or test the source code, and a fork can produce a neutral build
without access to any private asset repository.

## Neutral replacement workflow

1. Create replacement PNGs for:
   - `assets/images/icon_light.png` (square launcher source);
   - `assets/images/icon_adaptive_fg.png` (Android adaptive foreground);
   - `assets/images/icon_with_bg.png` and `assets/images/logo.png` (in-app
     placeholders).
2. Keep the same filenames and dimensions, or update the paths in
   `pubspec.yaml` and the consuming widgets.
3. Regenerate platform launcher artwork:

   ```bash
   dart run flutter_launcher_icons
   ```

4. For unsupported generated desktop/web runners that you choose to ship,
   replace their icon files listed in `TRADEMARKS.md` as well.
5. Change application display names and bundle/application identifiers before
   distributing a fork.
6. Run `flutter analyze`, `flutter test`, and a flavor build for each platform
   you distribute.

The replacement artwork may be a plain geometric mark or other assets you have
the right to distribute. Do not reuse the Palladin name or reserved artwork in
a way that implies an official release.

## Current official artwork: T02

The owner-approved 2026-09-09 mark is the T02 stepped shield without stripe gaps and the centered
negative-space hex (radius 34, border 15), R04 raster texture and `#E54645`.
`assets/images/logo.png` uses tight 96%-height framing and a transparent hex border.
`icon_light.png` and `icon_with_bg.png` are opaque white/dark artwork sources;
iOS and macOS derivatives preserve their platform dimensions. iOS icons are RGB.
Android uses the separate transparent `icon_android.png` legacy source and the
existing transparent adaptive foreground. Its adaptive background is white in
both day and night configurations; Android still controls the launcher mask and
may recolor themed icons. A wallpaper-transparent adaptive icon is not guaranteed.

Android adaptive foregrounds place the complete shield in the 66dp safe circle
within the 108dp layer. Legacy Android icons use 80% height for circular masks.
PWA maskable exports fit the central 40%-radius safe circle. Favicon and launcher
outputs at every size retain the same geometry and R04 grain.
The Android legacy exports have transparent margins and a transparent hex border.
Notification small icons use the same mark's alpha silhouette, with white RGB
and no raster grain colors, rather than the full-color launcher artwork.

Run `dart run tool/generate_android_icons.dart` to reproduce Android legacy and
notification PNGs from the approved `logo.png`, plus the separate opaque white
512px Play store artwork at `assets/store/google-play-icon.png` from
`icon_light.png`. No store artwork is used as a notification small icon.

All platform derivatives are committed. The coordinated source inventory is in
`assets/brand/` in the Palladin root repository; standalone forks can continue
using the replacement workflow above with their own assets.

The shared in-app BrandHero renders the mark at 72 logical pixels, separated from the 28 px wordmark by AppSpacing.xxl + AppSpacing.xs (28 logical pixels). Login, unlock and the privacy cover reuse this component. Launcher and favicon framing follow the platform-specific exports above.

AuthBrandHeader separates the wordmark from its rotating login copy or persistent unlock caption by AppSpacing.md (12 logical pixels).

PrimaryButton retains the full AppColors.brandRed background when disabled or loading. Disabled labels stay dimmed; unavailable actions remain non-interactive.
