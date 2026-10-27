# Android AutoFill emulator regression harness

This opt-in diagnostic harness compiles the repository's **actual** AutoFill Kotlin
sources and Android resources into an isolated debug provider. A second APK renders
native EditText and real Android WebView forms. Neither APK includes Flutter,
Firebase, an account, backend networking, release signing or an authentication
bypass. Release variants are disabled. The provider launcher creates only synthetic
records through the real encrypted-cache implementation and Android Keystore.

The harness is separate from application/PR builds. Run only with explicit local
Android build authorization, on a disposable emulator with a PIN and fingerprint
ID `1` enrolled. It changes that emulator's selected provider and the fixture's
App Link verification state. Never use this app with real credentials.

## Build and set up

Requirements: JDK 17+, Gradle 8.14, Android SDK platform 36/build tools, Python 3,
and an Android 12+ emulator with a biometric sensor and Gboard. Build plugins are
pinned to AGP 8.11.1 and Kotlin 2.4.10; AndroidX Biometric 1.1.0 and Autofill 1.3.0
match the application. Set `JAVA_HOME`, `ANDROID_HOME` and put `adb` on PATH.

From the repository root:

```sh
gradle -p tool/android-autofill-harness assembleDebug
adb -s emulator-5554 install -r tool/android-autofill-harness/provider/build/outputs/apk/debug/provider-debug.apk
adb -s emulator-5554 install -r tool/android-autofill-harness/form/build/outputs/apk/debug/form-debug.apk
adb -s emulator-5554 shell settings put secure autofill_service io.palladin.autofill.harness.provider/io.palladin.mobile.autofill.PalladinAutofillService
adb -s emulator-5554 shell settings put secure show_ime_with_hard_keyboard 1
adb -s emulator-5554 shell am start -n io.palladin.autofill.harness.provider/io.palladin.mobile.MainActivity
```

The launcher must show `Synthetic encrypted cache ready`. Enroll the emulator
fingerprint through Android Settings first, using `adb -s emulator-5554 emu finger
touch 1` for enrollment touches. The harness does not create or change a PIN.

## Exercise the real system flow

```sh
python3 tool/android-autofill-harness/exercise.py --serial emulator-5554 --mode native-login --fill
python3 tool/android-autofill-harness/exercise.py --serial emulator-5554 --mode native-username --fill
python3 tool/android-autofill-harness/exercise.py --serial emulator-5554 --mode web-login --fill
python3 tool/android-autofill-harness/exercise.py --serial emulator-5554 --mode web-username --fill
```

`--fill` checks the service's actual callback diagnosis, taps its inline keyboard
chip, asserts that the real biometric prompt appears, sends an emulator fingerprint,
and selects the returned dataset. Native forms additionally require the real
picker and **Fill once** warning. The form checks both expected fields (or just the
username for a first-step form) and exposes only `fillVerified=true/false`.
The runner prints outcomes, never form values or cache contents. Temporary UI XML
is removed after each read. The form has no INTERNET permission.

The runner sets `fixture.invalid` as OS-verified only for the WebView scenarios;
native scenarios clear that verification to exercise the explicit manual warning.
This is synthetic OS authority supplied by the test, not a claim of public domain
ownership. The provider build imports `<queries>` directly from the production manifest,
so package visibility cannot silently diverge from the application; there is no fixture-specific package allowlist.

The UI driver was verified on Pixel 10 Pro XL, 1344×2992, English Gboard. Its inline
chip is first sought by accessible text; on this AVD Gboard excludes its inline
surface from uiautomator XML, so the fallback coordinate is x=670/y=2050; adjust `--inline-y` for a different IME
layout. The fixture's focus coordinate also assumes that screen geometry. The
script is a focused emulator regression, not a device-independent UI framework.
For callback-only RED checks use `--expected REJECTED` without `--fill`.

## Recorded evidence — 2026-10-27

Environment: API 37 / Android 17 arm64 emulator, WebView 146.0.7680.177, Gboard.
Pre-fix production native code was compiled directly from baseline
`016dfca8bdbfe80367e961b050aa041d508cb338`. Synthetic cache, authentication and form data were
identical across the comparison.

| Form | Baseline | Fixed behavior |
| --- | --- | --- |
| Native username + password | `RESPONSE_OFFERED`, password count 1 | Full biometric/manual confirmation/dataset/field assertions pass |
| Native username only | `REJECTED`, password count 0, cache not checked | Full biometric/manual confirmation/dataset/field assertion passes |
| WebView username + password | `REJECTED`, password count 1, domains ambiguous | Full biometric/dataset/both-field assertions pass |
| WebView username only | `REJECTED`, password count 0, domains ambiguous | Full biometric/dataset/username assertion passes |

The real WebView container supplied an empty web-domain sentinel while both virtual
input nodes supplied the actual host. Counting the empty sentinel caused false
ambiguity. After correcting that parser behavior, the existing scheme-only HTTPS
visibility query still prevented the provider UID from reading the fixture's App
Link state (`NameNotFoundException`). The generic `android:host="*"` query restored
that independent OS lookup. An explicit fixture package was used temporarily to
isolate visibility, then removed before final verification.

This proves real Android callbacks, IME presentation, Keystore biometric auth,
selection and field handoff for these fixtures. It does not prove physical Samsung
behavior, third-party applications, Chrome's separate provider setting, app
unlock/cache publication from Flutter, or OEM biometric implementations. Existing
JVM and Flutter tests cover complementary boundaries. No emulator CI workflow is
added: deterministic CI would additionally need a provisioned emulator, enrolled
test biometric and fixed IME/display configuration.

## Cleanup

Restore the emulator's previous provider and keyboard setting, then uninstall only
`io.palladin.autofill.harness.provider` and `io.palladin.autofill.harness.form`.
Do not wipe an emulator or delete its profile. Build outputs and local tooling
state remain ignored; no APK, screenshot or cache is committed.
