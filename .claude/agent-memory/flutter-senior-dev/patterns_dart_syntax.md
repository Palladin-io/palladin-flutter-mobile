---
name: patterns-dart-syntax
description: Dart null-aware map elements and SizeTransition API gotchas in this Flutter project
metadata:
  type: feedback
---

# Dart / Flutter syntax gotchas confirmed in this project

**Null-aware map elements:** to conditionally include a map entry only when a
value is non-null, the `?` goes before the *value*, not the key:
`{'name': ?name, 'type': ?type}`. The analyzer's `use_null_aware_elements`
lint flags the older `if (x != null) 'key': x` form; `?'key': value` is wrong
and triggers `invalid_null_aware_operator`.

**Why:** Flutter 3.41 stable enables this lint. Saves a few lines vs imperative
`if (x != null) body['x'] = x`.

**How to apply:** prefer `'key': ?value` for optional PATCH/POST request body
maps in data sources.

**SizeTransition:** uses `axisAlignment` (a `double`, e.g. `-1.0`), NOT
`alignment`. A prior commit wrongly renamed it to `alignment` and broke
`flutter analyze`. If you see `undefined_named_parameter` on `SizeTransition`,
it's `axisAlignment`.

**Localized dates:** never hand-roll month-name arrays (`['Jan','Feb',…]`) —
they're English-only and a reviewer will flag them for PL users. Use
`intl`'s `DateFormat.MMMd(locale)` / `DateFormat`, passing
`Localizations.localeOf(context).toString()` threaded from the call site
(formatter helpers in `*_format.dart` take a `String locale` param). Locale
symbol data is auto-initialized by `GlobalMaterialLocalizations.delegate`
(already in `AppLocalizations.localizationsDelegates`), so no explicit
`initializeDateFormatting` is needed for `en`/`pl`. `intl: any` is already in
pubspec.
