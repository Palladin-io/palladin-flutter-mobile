# Mobile releases on demand

Status: approved by owner 2026-10-25; implementation authorized. No store upload yet.

## Objective and accepted decisions

The owner wants to install the latest approved mobile app on their own Android/iOS devices without a public launch. GitHub Actions plus Fastlane is the selected approach. A manual release must cover validation, version allocation, signed builds, store upload and automatic availability to configured internal testers.

Accepted requirements:
- Release source is main, resolved once to an immutable commit.
- Separate stg and prod applications can coexist on a device. stg starts disabled.
- Android uses Google Play Internal Testing; iOS uses TestFlight internal testers. No external beta or public store release.
- Marketing version defaults to unchanged; optional patch, minor, major or explicit version. Every new release gets a monotonically increasing build identity.
- Retrying upload reuses the original artifact and version.
- An optional GitHub draft release can collect notes and artifacts.

## Approaches

Selected: extend existing GitHub Actions builds with pinned Fastlane upload tooling. This preserves Flutter build commands, signing configuration and artifact attestations while using maintained store integrations.

Alternative: implement direct Google/Apple API upload clients. This avoids Fastlane but would add transport, authentication and processing-state maintenance. The owner selected the first approach on 2026-10-23.

## Scope and exclusions

Change the mobile repository's workflows, release scripts/tests, dependency lockfiles and release documentation. Keep PR checks free of APK/AAB/IPA builds. Do not alter unrelated app features or the owner's dirty checkout.

Do not publish publicly, accept legal agreements automatically, invite new testers automatically, change app identifiers or grant store permissions from a workflow. Initial app creation, tester membership and API access are provisioning prerequisites. Upload/distribution is automatic once those prerequisites are satisfied.

This automation does not waive the existing release blocker concerning persistent master-key biometric storage. Resolve and review that blocker before enabling real distribution; do not disable it merely to make CI green. Fixing app cryptography is a separate scoped change.

## User-facing workflow

Extend the existing mobile-store-builds.yml entry point, renamed in the UI to Mobile Release, to avoid parallel competing release paths. workflow_dispatch only; reject non-main refs even if a maintainer selects one.

Inputs:
- environment: prod (default), stg.
- platform: both (default), android, ios.
- operation: release (default), resume-upload.
- version_mode: keep (default), patch, minor, major, manual.
- version: required only for manual; otherwise empty.
- source_run_id: required only for resume-upload; otherwise empty.
- create_github_draft: false by default.

resume-upload rejects version changes and environment/platform mismatches. A platform subset of the original release is allowed, to resume only a failed platform.

A run summary shows source SHA, selected environment/API host, marketing version, platform build identifiers, tests, signing/build/upload/processing/distribution outcomes, artifacts and store links. A successful upload is not yet a successful distribution. Each platform has its own outcome; one failure must not erase another platform's completed result.

## Environment mapping

| Input | Flutter flavor | App identifier | Protected environment |
| --- | --- | --- | --- |
| prod | production | io.palladin.mobile | mobile-store-production |
| stg | staging | io.palladin.mobile.staging | mobile-store-staging |

CredentialProvider keeps the existing corresponding suffix. Retain separate Firebase, OAuth, signing and store app configuration per environment. API URLs come only from protected environment configuration; no real cloud values in runnable tracked defaults.

Design choice: prod selects the configured production backend, stg the configured staging backend. Remove the independent backend override from this release entry point to keep these two products predictable. This supersedes the old store-testing production-flavor/staging-backend recipe. The production DNS alias currently pointing to staging remains an external operational fact; this workflow does not migrate data or DNS.

stg fails preflight unless explicitly enabled by environment configuration. Missing configuration fails closed, before signing or upload. Preserve existing environment reviewer protections and main-only restrictions. One authorization at the release boundary covers automatic downstream upload; no extra handoff per platform.

## Source validation

Make Test reusable via workflow_call and manually runnable via workflow_dispatch, retaining existing PR/push triggers. Mobile Release invokes the same checks for its exact source SHA before signing. It must not depend on a previously available successful run or manufacture a trigger commit.

Preserve secret scanning, installer tests, notices, static analysis, structural budgets, Flutter tests and job summaries. Run checks without signing/store secrets. Action pins remain immutable. Test-only PR validation never creates mobile binaries.

## Version allocation and durable release record

Do not commit version bumps directly to main. Build overrides determine versionName/CFBundleShortVersionString and versionCode/CFBundleVersion; pubspec.yaml remains the bootstrap version.

Design choice: a dedicated, narrow metadata job reserves an immutable annotated Git tag under mobile-build/, targeting the source SHA. Its value-free metadata records schema, originating workflow run, environment, requested platforms, marketing version and build identities. This is the durable allocation ledger, independent of artifact retention and optional GitHub drafts.

Serialize release and resume runs at repository level with cancel-in-progress false. Do not rely on GitHub concurrency being a FIFO queue; superseded pending runs must not allocate versions. Allocate a global positive sequence using the highest existing reservation and configured migration floor. Confirm store-used numbers do not exceed that floor/reservation before the first rollout. Tag creation is create-only; conflicts must fail, never overwrite.

Version keep/bump uses the most recent reserved marketing version for the selected environment, initially pubspec.yaml. Reservations from failed releases remain used so retries and partial uploads cannot recycle versions. Manual versions must be canonical numeric X.Y.Z and cannot decrease the environment's reserved version. Platform encodings must obey Android and Apple numeric bounds, with explicit boundary tests; the exact counter encoding is an implementation decision documented before rollout.

A rerun of the same release run finds its existing reservation and verifies the same immutable inputs, rather than incrementing again. A new dispatch reserves a new number. Expired or deleted artifacts require a new release; never rebuild under an already uploaded identity.

## Build and artifact boundary

Reuse existing per-platform signing/build steps. Validate certificate/profile expiration, app and extension IDs and entitlements, including Associated Domains and App Groups, before the expensive iOS build. Preserve the existing cleanup of ephemeral signing assets before subsequent third-party artifact actions.

Both platforms use the same marketing version and sequence reservation. Persist signed AAB/IPA before uploading to stores. Retain SBOM and provenance attestations. Extend the release manifest with originating run, source SHA, environment, app identifiers, version/build identifiers, test result reference and artifact digests. Artifacts contain no signing or upload credentials.

A resume run uses the current reviewed main uploader, downloads artifacts from the explicitly selected original release workflow/run in this repository, verifies provenance and manifest/digests, validates the source commit remains reachable from main, then uploads only the requested original platform(s). It never executes code or dependency files from downloaded artifacts and never checks out an arbitrary user-supplied ref.

## Store delivery

Fastlane is pinned through Gemfile and Gemfile.lock. Run non-interactively with scoped credentials in protected upload jobs, separate from build jobs.

Android: target internal explicitly (never Fastlane's default production track), complete the internal release and verify the exact version code is active there. The existing configured tester list/group owns access. Do not rewrite store listing, screenshots, tester membership or other tracks. First-upload/draft-app restrictions must be reported as actionable provisioning blockers, not silently retried with weaker settings.

iOS: authenticate with an App Store Connect API key, not an Apple ID password/session. Upload without external distribution or review submission. Wait for processing with a bounded timeout and verify that the exact build is available to the configured internal group. Provision that group with automatic distribution enabled, and verify it is internal; do not treat Fastlane's external-groups option as internal group selection. A missing group, export-compliance hold, invalid binary or processing timeout must produce a non-success state with a resume path.

Retries reconcile store state first. If the exact release build is already uploaded/processing/distributed, continue processing/distribution or report completion without duplicate upload. Ambiguous accepted uploads wait/reconcile with a bounded deadline; they do not allocate another number or blindly repeat a write. Older resumed builds must never replace a newer active Android internal release: report superseded instead. An already-used identity from an unknown source requires manual reconciliation, not an assumption that its binary matches.

## Credentials and provisioning

Keep existing Android signing and Apple distribution inputs. Upload credentials are scoped to the corresponding app and least required store role. Prefer Google Workload Identity Federation with a narrowly restricted GitHub repository/environment identity; use App Store Connect API key material in protected GitHub secrets. Never print credentials, key files or full authentication errors containing tokens. No credentials in user input, command-line literals, checked-in defaults or artifacts.

Provisioning checklist is part of docs/mobile-store-builds.md: per-environment app records, tester access, Apple internal group ID, Google identity federation/service-account permissions, Apple API key, signing profiles and API/Firebase/OAuth configuration. Missing values must be listed by name without revealing contents. Creating/changing these external permissions is separate from implementing the workflow.

An optional GitHub draft uses the reserved source tag, release notes and verified build artifacts. It remains a draft and cannot publish a public release. GitHub draft failure is reported separately from an already completed store upload; resuming it cannot redistribute builds.

## Validation and acceptance

Use TDD for release logic. Test:
- prod/stg identity and backend mapping, disabled stg, missing configuration and non-main rejection;
- keep/patch/minor/major/manual, invalid/downgraded versions, numeric limits, initial migration floor, tag race, same-run rerun and failed reservations;
- wrong-repository/workflow/source/environment/platform manifests, tampered digests and expired artifacts;
- no public track/external beta paths, pending processing vs success, duplicate upload reconciliation, partial platform failures and older-build resume;
- absent/expired/mismatched iOS profiles and missing entitlements;
- credential cleanup on success, error and cancellation without value-bearing logs.

Validate YAML with actionlint and run script/Ruby tests with stubbed store responses. Run repository-native CI after the PR is ready under the owner's existing explicit CI authorization. Only after merge, provisioning and release blockers are resolved, run prod end-to-end: fresh release on both platforms, installation by the internal tester, and resume of the same release without new builds. stg disabled rejection must be demonstrated. Unit tests do not substitute for the real store acceptance.

## Current checkpoint

Accepted: environment split, automatic internal distribution, version modes, immutable upload retries, GitHub Actions + Fastlane. Worktree: .worktrees/mobile-release-20261023; branch: feat/mobile-on-demand-release. Original mobile checkout contains unrelated changes and remains untouched.

Completed: repository/workflow inspection, this design, and independent builder check (no important unanswered questions). Next: owner review, implementation plan, implementation/PR/CI, provisioning, end-to-end release. Known blockers: previous iOS profile lacks Associated Domains; master-key persistence remains release-blocking until resolved; store upload credentials/group configuration are not yet verified. No release success is claimed.

## References

- https://docs.fastlane.tools/actions/upload_to_play_store/
- https://docs.fastlane.tools/actions/upload_to_testflight/
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/
