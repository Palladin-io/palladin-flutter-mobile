# PR Review Criteria — Palladin Flutter Mobile

Detailed checklist for each review category. Load this file in full before starting the review.

---

## 1. BLoC Pattern

### Cubit vs Bloc selection
- **Cubit** for simple, linear state transitions (no events needed, just method calls).
- **Bloc** for complex flows where distinct event types drive different state transitions.
- Never use a raw `ChangeNotifier` or `ValueNotifier` for feature state — always BLoC/Cubit.

### State discipline
- State classes are **immutable** — use `copyWith` or `freezed`-generated classes. No mutable fields on state.
- State emitted from Cubit/Bloc methods, never mutated in place.
- `emit()` called only inside Cubit/Bloc — never from a widget.

### Widget / BLoC separation
- **No business logic in widgets.** Widgets only call BLoC methods and react to state.
- `BlocListener` for side effects (navigation, snackbars, analytics). `BlocBuilder` for UI rendering. `BlocConsumer` only when both are needed in the same widget.
- `context.read<XCubit>()` in callbacks; `context.watch<XCubit>()` or `BlocBuilder` in build methods — never `context.read` inside `build`.
- Dependency injection via `BlocProvider` / `MultiBlocProvider` at the right scope — not lower than needed.

### State lifecycle
- `close()` called (via `BlocProvider`'s auto-dispose or explicit `dispose()`) — no leaked Cubit/Bloc instances.
- `on<Event>` handlers in Bloc are `async` only when they perform async work.

---

## 2. Visual Consistency — Shared Components

### Input fields
- All text inputs use `OnboardingTextField` — no custom `TextField` with manual styling.
- All validation / feedback messages use `FieldFeedbackSlot` — no custom animated feedback widgets.
- Error state: pass `feedbackChild` + `feedbackVisible: true` + `borderColor: AppColors.brandRed` + `focusBorderColor: AppColors.brandRed`.
- Never duplicate the input animation or border logic inline.

### Buttons
- Primary actions use the `PrimaryButton` widget — no custom `ElevatedButton` with manual color/padding.

### Colors
- **All colors via `AppColors.*`** — no inline `Color(0xFFXXXXXX)`, `Colors.red`, `Color.fromARGB(…)`, or `Colors.white.withValues(alpha:…)` outside `app_colors.dart`.
- New colors must be added to `lib/core/theme/app_colors.dart` with a descriptive constant name and doc comment.
- Background gradient: `AppColors.darkBackgroundGradient` — no inline `LinearGradient` with the same stops.

### Theme
- App supports light and dark mode — default is dark, user can change in settings (persisted preference). Never hardcode `ThemeMode.dark` permanently.
- Conditional theming via `Theme.of(context).brightness` is valid — every widget must render correctly in both modes.

---

## 3. i18n — Internationalisation

- **No hardcoded user-facing strings** in Dart files — every visible string must be in `lib/l10n/app_en.arb` and `lib/l10n/app_pl.arb`.
- Use `AppLocalizations.of(context)!.keyName` to reference strings.
- Key naming convention: `featureActionOrLabel` (camelCase, no dots).
- Error messages in data/domain layer use **typed exception enums** — translation happens at the presentation layer where `BuildContext` is available.
- After adding or changing ARB keys, `flutter gen-l10n` must be run (generated files in `lib/l10n/generated/` should be up to date with the ARB changes in the PR).
- Both `app_en.arb` and `app_pl.arb` must be updated together — no key present in one but missing in the other.

---

## 4. Security

- **No sensitive data in logs** — master passwords, private keys, tokens, mnemonics must never appear in `debugPrint`, `print`, or logger calls.
- **Secure storage** — sensitive values (tokens, keys) must be stored via `flutter_secure_storage` (OS Keychain / Android Keystore), never in plain `SharedPreferences`.
- **No keys in Dart state that could be serialized** — in-memory key buffers must not be placed in serializable state objects or passed to analytics.
- **No hardcoded secrets** — no API keys, base URLs for production in source; use `EnvConfig` flavors.

---

## 5. Analytics

- Format: `mb:{module}:{event}` — e.g., `mb:unlock:page-viewed`, `mb:onboarding:setup-page-viewed`.
- Only **UI events** — page views, biometric usage, push notification taps. No business logic events (those are tracked by the backend).
- Invocation: `AnalyticsService.instance.capture('module', 'event')` — the `mb:` prefix is added internally.
- Analytics calls belong in `initState` (page-viewed), `BlocListener` side effects, or user interaction callbacks — **never** in `build()` or `BlocBuilder.builder`.
- No duplicate events: if the backend tracks an action, the mobile must not also fire a matching event.

---

## 6. Mobile Best Practices

### Widget lifecycle
- `TextEditingController`, `AnimationController`, `ScrollController`, and similar resources disposed in `dispose()`.
- `addListener` in `initState` balanced by `removeListener` in `dispose()`.
- `mounted` checked before calling `setState` or `context.*` after any `await`.

### Navigation
- Routing via `go_router` (`context.go`, `context.push`) — no raw `Navigator.push` unless go_router cannot handle the case.
- Route paths defined in the router config, not scattered as string literals across widgets.

### Dependency injection
- Services and repositories injected via `get_it` + `@injectable` / `@lazySingleton` annotations — no manual `ServiceLocator` calls in widgets.
- `getIt<T>()` only in `BlocProvider.create` or top-level DI setup — not inside widget `build` methods.

### Performance
- No expensive synchronous computation (crypto, parsing) on the main isolate — use `compute()` or a separate isolate.
- `const` constructors used on stateless widgets where possible.
- No `setState` calls that rebuild more of the tree than needed.

---

## 7. Code Quality — DRY · SRP · OCP · Clean Code

- Shared widgets extracted to `presentation/widgets/` — not duplicated across pages.
- No business logic in `build()` — derive display values from state, don't compute them inline.
- Clear, descriptive method and variable names — code reads like prose.
- Private helpers extracted for non-trivial logic blocks (readability over brevity in long `build` methods).
- No dead code, commented-out blocks, or TODO comments left in the PR.
- `const` used on widgets and values wherever Dart allows.

---

## 8. Tests

- Widget tests for complex interactive widgets (forms, animated feedback, multi-step flows).
- Unit tests for domain logic (`evaluatePasswordStrength`, `pickVerificationIndices`, crypto helpers).
- New screens should have at minimum a smoke test confirming they render without throwing.
- `flutter test` must pass — no test left broken or skipped without justification.

---

## 9. Light & Dark Mode

**Design intent: the app supports both light and dark mode.** Default is dark; user can change it in settings (persisted preference). Every widget must render correctly in both themes.

- Flag `ThemeMode.dark` or `ThemeMode.light` hardcoded permanently — theme must follow the persisted user preference.
- `Theme.of(context).brightness` checks are valid for conditional theming — but must always use `AppColors.*`, never raw `Color(0xFF…)` inline.
- Flag `Colors.white`, `Colors.black`, `Colors.red`, `Color(0xFFXXXXXX)`, `Color.fromARGB(…)`, or `Colors.white.withValues(alpha:…)` outside `lib/core/theme/app_colors.dart`.
- New color constants must be added to `AppColors` with light and dark variants — no one-off inline values in widgets.
- If a widget is only tested/verified in dark mode without a corresponding light mode check: flag it.

## 10. Over-Engineering Check

Flag any of the following:
- A new abstraction (base class, mixin, generic widget) with a single concrete use.
- A BLoC where a `StatefulWidget` with local state would suffice.
- A new DI service registration for a stateless utility that could be a plain function.
- More than two layers of widget composition to achieve a simple visual effect.
- Speculative configurability (parameters, flags) added for hypothetical future use.
