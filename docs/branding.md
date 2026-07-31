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
