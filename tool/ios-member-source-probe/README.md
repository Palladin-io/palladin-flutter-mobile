# iOS canonical Member-source runtime gate

This disposable simulator host uses synthetic fixtures only. It compiles the
production CredentialProvider Swift source list and uses the same checkout's
Flutter App.framework, sqflite and libsodium. It never accesses a real account,
network, Runner storage, or a Palladin App Group. Generated artifacts stay in
`build/` and must not be committed.

Prepare normal **Debug-local simulator** CredentialProvider artifacts in
`build/ios-provider-gate` (the `CredentialProviderRuntime` build-only scheme may be
generated locally with xcodeproj, containing only the CredentialProvider target).
Do not globally override PRODUCT_BUNDLE_IDENTIFIER: Xcode applies that override to
Pods too, producing duplicate framework bundle identifiers.

```
flutter test tool/ios-member-source-probe/prepare_fixture_test.dart
ruby tool/ios-member-source-probe/project.rb
xcodebuild -project build/ios-member-source-probe/MemberProbe.xcodeproj \
  -scheme SyntheticMemberHost -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/ios-member-source-probe/derived ARCHS=arm64 build
```

Install the generated SyntheticMemberHost.app on a disposable simulator, launch
it, then enable **Synthetic Member** in Settings → General → AutoFill & Passwords.
Use its empty password field → Passwords → Synthetic Member. Unlock with the
public fixture password `synthetic-master-password`, select Synthetic, confirm
**Fill once**, then press **Check synthetic fill** in the host. Its sole success
marker is `SYNTHETIC_MEMBER_HANDOFF_PASS` after checking both known fixture values;
no credentials are printed. The extension must show an unverified-destination
warning because the synthetic native form has no associated HTTPS domain.

The gate exposed an actual Flutter lifecycle crash: installing a channel handler
before `FlutterEngine.run` raises NSInternalInconsistencyException. Production now
runs the engine, registers sqflite, then installs the request channel. On
2026-11-04, the actual OS-launched extension completed password KDF → readonly
SQLite → metadata-only list → explicit selection → selected body reveal →
source-fenced OS handoff; the host reported PASS at 19:48:13 local time. Native
negative tests additionally cover cancellation, wrong origin/account, expired
lease, replay and source invalidation; Dart tests cover wrong password and key
cleanup.

A simulator Debug/JIT pass is **not** a physical iPhone Release memory/biometric
certification. The unsigned device Release/AOT extension compiles, but a signed
physical-device gate remains mandatory before iOS publication. No TestFlight or
App Store upload is authorized by this harness.

The explicit capabilities dictionary also declares `ProvidesPasswords = true`.
Apple documents its default as `NO`; save/generate capabilities do not substitute
for password-provider registration:
https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionattributes/ascredentialproviderextensioncapabilities/providespasswords
The synthetic host must carry the same AutoFill entitlement as Runner; omitting
that host entitlement hides the provider even when PlugInKit discovers it.
