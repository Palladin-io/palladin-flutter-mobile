# Mobile Release

`Mobile Release` is a manually dispatched GitHub Actions workflow. It validates main, reserves a version, builds signed artifacts and distributes them to internal testers through Fastlane. A GitHub workflow success means the requested store distribution was confirmed; a build alone does not establish that a tester can install it.

## Inputs

- `environment`: `prod` (default) or `stg`. These are separate applications, with production/staging backends respectively. There is no independent backend override.
- `platform`: `both`, `android`, `ios`.
- `operation`: `release` or `resume-upload`.
- `version_mode`: `keep`, `patch`, `minor`, `major`, `manual`.
- `version`: numeric `X.Y.Z`, only for manual mode.
- `source_run_id`: original Mobile Release run ID, only for resume.
- `create_github_draft`: optionally create/update a **draft** GitHub release containing verified binaries.

Select main. Non-main dispatches fail preflight. Test remains available for PR/push, manual execution and reusable invocation, without application builds. Mobile Release calls it for the exact source commit.

iOS artifacts explicitly use Xcode 26.3 on `macos-15`. CredentialProvider uses
[generated-password APIs introduced in iOS 26.2](https://developer.apple.com/documentation/authenticationservices/asgeneratepasswordsrequest);
runtime availability annotations cannot make these types compile against an older SDK.
The release job logs the selected toolchain and typechecks the API contract before
loading signing inputs. The [runner image used by the first failed release](https://github.com/actions/runner-images/blob/macos-15-arm64/20260907.0337/images/macos/macos-15-arm64-Readme.md)
provides Xcode 26.3/iOS 26.2, but defaults to Xcode 16.4/iOS 18.5. Keep this explicit
selection compatible with the installed runner image when upgrading toolchains.

| Environment | Flavor | Package / bundle | Protected GitHub environment |
| --- | --- | --- | --- |
| prod | production | io.palladin.mobile | mobile-store-production |
| stg | staging | io.palladin.mobile.staging | mobile-store-staging |

The iOS extension uses the matching `.CredentialProvider` suffix. `stg` is disabled unless repository variable `MOBILE_STAGING_ENABLED=true`. A disabled environment is rejected before signing. Keep protected environments restricted to main and retain required reviewers. GitHub may request environment approval for separate build/upload jobs; the workflow does not bypass these protections. Once authorized, store upload and tester assignment require no separate manual publication.

## Version identity

`pubspec.yaml` is the bootstrap marketing version. Later keep/bump operations use the last reservation for the selected environment. Failed reservations remain consumed. Manual versions cannot decrease. No version commits are pushed to main.

Repository variable `MOBILE_BUILD_SEQUENCE_FLOOR` is required. Before initial enablement, compare it against **all existing store builds**, including manually uploaded builds. Android uses the global sequence directly. iOS uses `(sequence // 10000 + 1).((sequence // 100) % 100).(sequence % 100)`, giving sequence 1 → `1.0.1`, 10000 → `2.0.0`; max sequence is 99,989,999. To migrate an existing iOS A.B.C build, its equivalent sequence is `(A-1)*10000+B*100+C`. The floor must be at least the greater of the used Android number and converted iOS number. Do not manually upload future colliding numbers.

Create-only annotated tags `mobile-build/<run-id>` reserve source, environment, version and sequence. Do not move/delete these tags. Restrict modification of the `mobile-build/` and `mobile-upload/` namespaces to trusted release operators/workflows. Metadata jobs need contents:write solely for these records; upload jobs also record a create-only upload intent containing the verified manifest. No secrets are stored in these tags.

The workflow serializes releases, but GitHub does not promise a FIFO pending queue. A canceled pending dispatch has not necessarily reserved a version. Inspect its summary rather than assuming it ran.

## Resume and partial failures

Use `resume-upload` with the original run ID and matching environment; choose both original platforms or a subset. Version mode must remain keep. The current main uploader checks the original workflow, main source reachability, reservation, manifest provenance and artifact SHA-256. It never rebuilds the application or executes downloaded code.

Artifacts are retained for 30 days. Expired/missing artifacts require a **new release**. Do not rerun all jobs to rebuild an already reserved number; build jobs explicitly reject rerun attempts. A store timeout can mean an upload was accepted. The upload intent allows polling the same attempt; it must not be removed merely to force another upload. An absent build after an attempted upload or an unknown pre-existing iOS identity requires operator reconciliation. A confirmed older Android build is reported as superseded rather than replacing a newer internal track release.

Each platform has separate upload results, and a failed platform does not cancel the other. Resume just the missing platform. GitHub draft creation is separate from store delivery; its failure does not undo a successful upload. Drafts remain unpublished.

## Provisioning

No store passwords or 2FA sessions are used. Never paste private keys into issue bodies, workflow inputs or logs.

Repository variables:
- `MOBILE_BUILD_SEQUENCE_FLOOR`: audited migration floor.
- `MOBILE_STAGING_ENABLED`: absent/false initially.

For each protected environment configure:
- `MOBILE_DISTRIBUTION_ENABLED`: keep absent/false until device-bound biometric protection and actual key deletion pass review and automated checks, and the prerequisites below are verified. Internal distribution supplies builds for device acceptance; physical-device acceptance is required before broad/public release. This flag is not a waiver.
- `PRODUCTION_API_BASE_URL` / `STAGING_API_BASE_URL` as appropriate: explicit HTTPS URL.
- corresponding `PRODUCTION_GOOGLE_SERVER_CLIENT_ID` / `STAGING_GOOGLE_SERVER_CLIENT_ID`.
- `GOOGLE_IOS_CLIENT_ID`, `FIREBASE_ANDROID_CONFIG`, `FIREBASE_IOS_CONFIG` for that app identity.
- `APP_GROUP_IDENTIFIER`: exact configured Xcode App Group, not an inferred value.
- `GOOGLE_PLAY_WORKLOAD_IDENTITY_PROVIDER`, `GOOGLE_PLAY_SERVICE_ACCOUNT`: Google Workload Identity Federation restricted to this repository, main and the exact environment. Grant only the app-scoped permissions needed for testing-track releases; do not grant production publication for this flow.
- `TESTFLIGHT_INTERNAL_GROUP_ID`: existing internal group with automatic access to builds; ensure the intended App Store Connect user is a member. Public/external beta is not enabled.

Signing secrets (existing names retained):
- `ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`, `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_TEAM_ID`.
- `IOS_PROVISIONING_PROFILE_PRODUCTION_BASE64` and `IOS_PROVISIONING_PROFILE_PRODUCTION_CREDENTIAL_PROVIDER_BASE64`; corresponding STAGING names for stg.

Upload secrets:
- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_BASE64`: App Store Connect API key with the least role/app access sufficient to upload and inspect builds/groups.

Create store app records and tester lists once. Accept required agreements and complete required app/export-compliance declarations through the owner-controlled process. An initial Play app still restricted to draft releases cannot silently become a completed internal release: finish its provisioning first. A compliance hold in TestFlight is not a successful release.

Apple profiles must be App Store distribution profiles for the app and CredentialProvider, matching the certificate, team, App Group and AutoFill entitlement. The app profile must include Associated Domains. The workflow validates these before building and removes signing assets afterward.

## Validation and current limits

Local: `python3 -m unittest discover -s tool/tests`, `bundle exec ruby fastlane/tests/mobile_delivery_test.rb`, `actionlint .github/workflows/*.yml`. The reusable Test workflow also runs Flutter checks, secret scan and existing budgets.

Real acceptance remains required after merge and provisioning: install both internal builds on devices, then resume the same run without new binaries. The historical iOS profile lacking Associated Domains and the biometric cleanup and physical-device validation gates are not solved by release automation. No real store success can be inferred from the script tests.
