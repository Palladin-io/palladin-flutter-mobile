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
and an Android 12+ emulator with a biometric sensor. A keyboard without inline
suggestions can exercise the standard dropdown fallback. Build plugins are
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

The runner sets `fixture.invalid` to the emulator OS approved state (`pm set-app-links`
state 2, exposed to the app as verified) only for the WebView scenarios. Unlike
overridable verification state 1, this cannot race with asynchronous installation
verification of the reserved `.invalid` host;
native scenarios clear that verification to exercise the explicit manual warning.
This is synthetic OS authority supplied by the test, not a claim of public domain
ownership. The provider build imports `<queries>` directly from the production manifest,
so package visibility cannot silently diverge from the application; there is no fixture-specific package allowlist.

The UI driver focuses the synthetic app's enabled EditText accessibility nodes
and taps suggestions by their observed bounds. It has no hardcoded screen or
keyboard coordinates. When an inline surface is inaccessible or ignored, the
fixture's explicit Request Autofill button can expose the standard dropdown.
Absence of a usable suggestion fails the test instead of guessing a tap location.
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

## Authoritative validation of a committed checkout

The provider Gradle module also compiles all native JVM tests directly from this
checkout's `android/app/src/test/kotlin/io/palladin/mobile/autofill`. Production
Kotlin, resources, manifest queries, JVM tests and APKs therefore share one source
authority. No temporary compiler script, copied production class or old jar is
used. Run the focused JVM gate with `:provider:testDebugUnitTest`.

After committing all intended changes, with the emulator unlocked and fingerprint
`1` enrolled:

```sh
python3 tool/android-autofill-harness/validate.py --serial emulator-5554 --gradle /path/to/gradle
```

This rejects a dirty checkout, runs Gradle `clean`, the native JVM suite and debug
APK build, installs those APKs, and runs the response and OS cases below. It checks
that the commit and clean state are unchanged afterwards. Successful evidence is
written to ignored `tool/android-autofill-harness/build/validation.json`: full Git
SHA, checkout path, APK SHA-256 digests, JVM test count and individual observed
outcomes. The prior provider and keyboard settings are restored in `finally`.
Do not edit source after this run and still attribute its evidence to a later SHA.

### Actual authentication response inspection

`exercise.py --inspect-response` starts the real `AutofillAuthenticationActivity`
for result from the synthetic launcher, using real Android View AutofillIds and
the real encrypted fixture/cache. It traverses `completeFill` for WEB and
`selectionResponse` for MANUAL_NATIVE after biometric authentication. For both
username-only and two-field requests it checks the returned **actual FillResponse**:
one dataset, exactly the intended field IDs, exactly the corresponding value count,
and the expected synthetic username/password in each field. Only a boolean result
leaves the in-memory assertion. This is complementary to the separate real
service → keyboard → biometric → OS field-handoff test; it does not replace it.

Android hides the response getters from ordinary applications. Only this inspection
case temporarily sets the selected emulator's `hidden_api_policy=1` to inspect the
returned object through reflection, restoring the previous setting in `finally`
even on failure. This does not alter any product origin/cache/authentication gate.
The subsequent full OS flows require the original/default policy restored.
Physical device serials and Python `-O` are rejected. Zero-target WEB and MANUAL_NATIVE requests traverse the authenticated activity
paths and assert cancellation with **no FillResponse**. HTTP and missing-scheme
inspection requests also assert cancellation with **no FillResponse**.

### Negative form coverage and baseline reproduction

The synthetic forms include search, OTP, password confirmation, hidden, disabled,
and non-text-container fields. Explicit manual Autofill requests capture a real
AssistStructure even when an ordinary focus event does not automatically request
credentials. Unsupported/insecure framework behavior is never reported as a
successful provider rejection.

On baseline `ca6bb9719386bdbf7986346a3b2bb1aadd661654`, the actual provider incorrectly
offered a response for native confirmation/hidden/disabled fields and WebView
search/confirmation/disabled fields. Native search/OTP/container and WebView
OTP/hidden fixtures already rejected. These are behavioral RED observations,
not source-string assertions. The current native JVM tests cover malformed and
missing scheme metadata and eligibility boundaries that cannot be emitted by a
particular WebView version.

On the recorded WebView, an HTTP `loadDataWithBaseURL` form produced no provider
callback even after an explicit manual request. The runner reports that separate
outcome as `FRAMEWORK_SUPPRESSED`; it must not be cited as proof that the production
service rejected an HTTP AssistStructure. The actual activity HTTP/missing-scheme
negative response tests and native scheme-policy JVM regressions cover the
application boundary. HTTPS metadata observed in the real framework had
`webScheme=https`, text Autofill type, enabled state and visible state.

## Presentation regression preview

The debug-only `PresentationPreviewActivity` applies the production RemoteViews
and constructs the production AndroidX inline content without opening the cache
or asking for biometric authentication. Run each combination of `language` (`en`,
`pl`) and `night` (`false`, `true`):

```sh
adb -s emulator-5556 shell am start -S -n io.palladin.autofill.harness.provider/io.palladin.mobile.PresentationPreviewActivity --es language pl --ez night true
```

`validate.py` runs all four previews through `presentation.py`, records their
assertion results, and saves screenshots under ignored `build/presentation/`.
The activity checks localized inline title and accessibility description, icon
presence, exact synthetic username/label/host values, single-line ellipsis,
duplicate-label suppression, and a decorative credential logo excluded from
accessibility. It renders the real dropdown layouts at 130% font scale, including
long synthetic strings, and displays `presentationVerified=true` only after every
assertion passes. Capture the rendered screen for light/dark visual review; no
real data is used. This verifies content/layout independently of keyboard policy;
it does not prove Gboard or Samsung Keyboard will display an inline suggestion.
Physical-device QA must still check both keyboards, light/dark modes, EN/PL,
TalkBack, large fonts, and dropdown fallback when inline is unavailable or ignored.

## Opt-in CI runtime gate

The normal PR job does not build APKs. With explicit CI/emulator authorization,
dispatch `test.yml` on the intended feature branch with `autofill_presentations=true`.
This opt-in job uses an isolated API 35 x86_64 AVD with KVM and the default IME.
It runs UI-driver regressions, creates a synthetic PIN, enrolls fingerprint 1
through the real Android Settings flow, and invokes `validate.py` on the clean
committed checkout. The validator compiles only the synthetic provider/form APKs,
runs native JVM tests, four localized presentation checks and all 24 response/OS
cases. No Flutter APK, account, real credential or production signing is involved.

Artifacts retain the commit identity, emulator startup diagnostics, synthetic
enrollment/presentation screenshots and successful `validation.json` including APK
hashes and observed case outcomes. A failed or partial run never creates a
successful validation report. This CI gate does not establish physical Gboard,
Samsung Keyboard or third-party application compatibility.
