# Actual Flutter/native request ownership fixture

This debug-only fixture compiles the unchanged production MainActivity, request bridge,
source fence and SourceAutofillAuthenticationActivity with a controlled Dart root.
It has a separate application ID, no INTERNET permission, no Firebase provider or cloud
configuration, no production account, and refuses release signing material. The runner
accepts only an explicit emulator serial. No authentication bypass is installed.

The synthetic target creates real AutofillIds and opens the native owner. Flutter reads
RAM-only pending metadata, begins a synthetic quarantined source, binds that request,
asserts that a fabricated authorization is rejected, and cancels through the real method
channel. The original owner must receive RESULT_CANCELED. The test repeats with the
existing MainActivity task. The one-second hold permits the original owner to stop behind
Flutter; it is test-only, not a production debounce.

From the Android project directory, with JAVA_HOME, ANDROID_HOME and Flutter configured:

```sh
CI=false gradle --no-daemon :app:assembleLocalDebug \
  -I ../tool/android-autofill-source-harness/synthetic-debug.init.gradle \
  -Ptarget=tool/android-autofill-source-harness/main.dart \
  -Ptarget-platform=android-arm64 -Psplit-per-abi=true
```

Use `android-x64` and the corresponding APK for an x86_64 emulator. From the repository:

```sh
python3 tool/android-autofill-source-harness/run.py \
  --adb "$ANDROID_HOME/platform-tools/adb" --serial emulator-5580 \
  --aapt "$ANDROID_HOME/build-tools/37.0.0/aapt" \
  --apk build/app/outputs/apk/local/debug/app-local-arm64-v8a-debug.apk
```

Negative control: build with `-PsourceOwnerNoHistory=true`. The same runner must fail
because the result owner is lost when Flutter becomes foreground. Default false matches
the production source-owner manifest. This negative override is invocation-only.

Observed on API35 ARM64: negative control failed waiting for SOURCE_OWNER_CANCEL_PASS;
default owner passed cold and warm channel/ownership checks. This is not evidence of
successful biometric fill, Member ciphertext decryption, system AutofillManager delivery,
or third-party browser/application compatibility. Those require the integrated source
controller and real request authentication tests. The fixture never configures production accounts or releases.

## System service admission regression

Build/install the existing `tool/android-autofill-harness` form APK, then run:

```sh
python3 tool/android-autofill-source-harness/service.py \
  --adb "$ANDROID_HOME/platform-tools/adb" --serial emulator-5580
```

The selected service is restored afterward. No native credential cache is provisioned.
Before cutover, native login returned REJECTED. After cutover, full login and username-only
return RESPONSE_OFFERED; OTP remains REJECTED. The separate cold/warm fixture also checks
username-only request handoff. Search and HTTP WebView requests were suppressed by the
framework in this run (no service diagnosis); they are not reported as runtime passes.
Existing classifier and origin-policy unit regressions retain search, OTP, confirmation,
hidden/disabled, cleartext/missing/mixed schemes and unverified origins coverage.

## Retired PendingIntent boundary

The runner also invokes the legacy non-generation Activity with an inert, public marker
in the synthetic package's old cache location. Before retirement, the old credential path
reached cache maintenance and deleted this marker (LEGACY_CACHE_TOUCHED). It must now return
canceled before cache construction, leaving the marker untouched. The fixture removes
the marker afterward. `--legacy-only` runs this negative migration test alone.

The old native harness's direct credential inspector targets the retired Activity and is
therefore no longer positive fill evidence; it must be migrated to the integrated canonical
source controller before that end-to-end CI gate can be claimed passing. Generated-password
and save fixtures remain separate; this guard does not change their format or lifecycle.

The actual channel fixture additionally checks live authorization revocation followed by
authoritative activation of the returned epoch by the same app session. Cold snapshot
revocation still destroys that session; live request revocation must cancel request/auth
without making source repair permanently fail with SOURCE_STALE_SESSION.

## Protected offline bootstrap

The fixture seeds only synthetic encrypted account text and public KDF metadata. After
live repair it kills the entire provider process, then verifies `sourceConfiguration`
against independently supplied full expected claims. Wrong organization is refused.
Exact ACTIVE configuration can be adopted only with explicit `forceQuarantine=false`;
forced quarantine makes the getter unavailable. The native fence authenticates this
configuration and its canonical account digest. Legacy records without the projection
do not authorize fallback. No account token, MK, decrypted private key or Entry body is
stored by this control record. Actual Entry lease/crypto checks remain mandatory later.

Each source request also exercises routine invalidation and requires `sourceChanged` to
carry its original request ID while `pending` retains that request. This is UI coherence
evidence only; selected-read epoch validation remains the native handoff boundary.
