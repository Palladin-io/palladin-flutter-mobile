# Synthetic Android password-save handoff

This opt-in emulator regression covers the real Android `SaveInfo` → OS save
prompt → `PalladinAutofillService.onSaveRequest` → opaque `IntentSender` →
production `MainActivity` → production Flutter `AutoFillSaveController.onDraft`
path. It uses two debug APKs and no additional application dependencies.

The provider APK compiles the normal application native sources unchanged. Its
alternate Dart entrypoint starts only the real save controller and a small test
surface. A fixed synthetic principal substitutes for an already unlocked account;
this does not exercise login, `AuthBloc`, Vault selection, encryption or Entry
creation. No backend, Firebase, analytics bootstrap, real credentials, MK or VK
are involved. The fixture never invokes a Vault write. Its in-memory assertions
check the exact synthetic source/domain, both captured values, native validation,
and one-time consumption. Only boolean scenario results are displayed or recorded.

The separate native form APK contains real username/password EditTexts. After the
real fill callback, a button changes both fields to fixed synthetic values, and
Submit invokes the public `AutofillManager.commit()`. The driver must observe and
press Android's actual Save button; calling `onSaveRequest` directly is not a
substitute. No autofill dataset is selected, so this save-only path needs neither
Gboard nor fingerprint enrollment. The form suppresses its software keyboard to
keep the three fixture controls accessible; it does not alter AssistStructure,
origin validation, production field parsing, or the OS save UI.

The test marks only the reserved `fixture.invalid` host OS-verified for the
synthetic form package using emulator `pm set-app-links` state `2`. This is
explicit test authority, not public domain ownership. The production verifier
still resolves the exact native host set and signing identity through Android.

## Guarded build

Use an isolated checkout, JDK 17, the repository's Gradle 8.14, Flutter, Android
SDK 36/build-tools 36.0.0 and an API 35+ **x86_64 disposable emulator**. Builds and
emulator execution require explicit authorization. No store workflow is used.

```sh
python3 -m unittest discover -s tool/android-autofill-save-harness/test -p 'test_*.py'
flutter test --no-pub tool/android-autofill-save-harness/test/synthetic_draft_test.dart
flutter analyze --no-pub tool/android-autofill-save-harness/main.dart tool/android-autofill-save-harness/test/synthetic_draft_test.dart
python3 tool/android-autofill-save-harness/build.py \
  --gradle /path/to/gradle-8.14/bin/gradle \
  --aapt "$ANDROID_HOME/build-tools/36.0.0/aapt"
```

`synthetic-debug.init.gradle` follows the existing Member benchmark's invocation
pattern. It permits only `:app:assembleLocalDebug` with this exact entrypoint,
rejects release signing material, gives the APK a separate
`io.palladin.autofill.savefixture.local` identity, and replaces only the debug
manifest for this invocation. That manifest removes INTERNET and Firebase's
initialization provider. The Google Services task receives no JSON inputs;
existing developer cloud configuration is not selected or copied. Its old
generated output is removed before running with the missing-config strategy.
Normal product build files and their release guards are unchanged.

The builder sets `CI=false` **only in that task/target-guarded debug subprocess**
because the application configuration otherwise demands a release keystore even
for a CI debug invocation. Do not set this globally or use it for release tasks.
The separate form project disables release variants. No signing credentials or
cloud identifiers are generated. The builder checks both final APK identities,
the absence of network permission/Firebase initialization and cloud client
resources, and the presence of the real MainActivity. APKs and reports stay under
ignored build directories. It writes their hashes and the source revision to
`build/artifacts.json`.

A dirty-tree build is useful only for compilation feedback and is marked
`sourceClean: false`. Runtime evidence requires a fresh build from the final clean
committed checkout; the driver refuses a dirty build, different commit or changed
APK hash.

## Isolated CI runtime

The existing Test workflow exposes an opt-in `autofill_save` dispatch input.
Its separate job runs the existing production native JVM suite, builds these
APKs and runs the three cases on a fresh official
API-35 x86_64 KVM emulator; ordinary PR checks remain unchanged. It uploads only
boolean/source/hash JSON, whitelisted role/bounds metadata, ADB version, emulator
startup diagnostics and a synthetic failure screenshot, never
APKs, UI dumps or the runner's ephemeral ADB key. The SDK's ADB server starts
before the emulator, so its authentication key exists before the guest connects.

To run the same driver manually, provision a fresh English API-35 `google_apis;x86_64` AVD, boot it with KVM and
bounded boot/adb timeouts, then run:

```sh
python3 tool/android-autofill-save-harness/exercise.py --serial emulator-5554
```

The driver installs/clears only the two synthetic packages, saves the selected
provider, installs the test host authority, and runs three cases:

1. OS Save launches the real MainActivity and delivers one valid draft through
   the real controller; re-consuming that native capture returns no value.
2. The controller temporarily treats the synthetic account as locked, leaving a
   real pending OS save unconsumed; explicit revoke removes it, and unlocking a
   new synthetic session cannot recover it.
3. The same held pending state is observed before force-stopping the provider;
   a fresh MainActivity/controller process probes native pending state before
   any cancel/revoke/activate call and must observe an empty slot. Explicit Arm
   is a later action, so initialization cannot erase evidence of persistence.

The driver reads all interactive windows using API 35's public
`uiautomator dump --windows`. A temporarily unavailable root yields no nodes
within the existing bounded wait; stale XML is removed before capture. It never
counts an unavailable hierarchy as success. During the initial cold-start gate
only, it may dismiss one exact system-owned “Pixel Launcher isn't responding”
dialog using its unambiguous enabled Close app button, within the same deadline.
Other or ambiguous ANRs fail normally. `dismissedLauncherAnr` records this action
in the validation/failure JSON; all three real save cases remain mandatory. Temporary UI XML is deleted after
each read and never printed or uploaded. On failure, `build/failure.json` records
only the fixed scenario, source commit and booleans indicating expected fixture
processes, resumed activities and service callback presence (null if inspection
was unavailable). Hierarchy metadata contains only whitelisted roles, numeric
bounds and known labels mapped to booleans; no arbitrary device text or intent
contents is retained. Flutter labels match exact `content-desc` as well as native
`text`, with enabled-state and tap-bounds checks. On this fresh synthetic AVD,
a failure screenshot is captured only while a fixture activity is foregrounded. The
result is boolean-only `build/validation.json`, bound to the source commit and
APK hashes. The previous AutoFill provider is restored in `finally`; synthetic
processes are stopped. Destroy the CI AVD afterwards. Do not collect general
logcat, real account state or form dumps as evidence. Never run this fixture on
an emulator containing real accounts or data.

Compilation and unit checks do not establish that these runtime cases pass.
Only a completed `exercise.py` run does. Real Samsung/Chrome behavior, biometrics,
app login/unlock, confirmation UI and canonical Vault creation remain separate
acceptance boundaries.
