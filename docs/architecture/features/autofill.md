# System AutoFill

## Current state

- Flutter rebuilds a dedicated native cache after vault unlock, committed
  policy-2 snapshot/delta repair, and vault or entry mutations. Rebuild reads
  only the complete local `MemberIndex + MemberSecret + EntryKey` generation;
  it never calls a legacy Entry list/detail/reveal projection or one endpoint
  per credential. Vault v2 credentials are eligible only when the current
  MemberIndex explicitly authorizes one or more exact AutoFill domains and its
  revision/key version matches the revealed member ciphertext.
- iOS embeds a signed `ASCredentialProviderExtension`, publishes credential
  identities to `ASCredentialIdentityStore`, and releases credentials only
  after Keychain biometric authorization.
  Its `NSExtensionPointIdentifier` is Apple's registered
  `com.apple.authentication-services-credential-provider-ui` value; a shortened
  value can compile and sign but is rejected during App Store validation.
  The parsed plist contract is covered by `tool/tests/test_ios_extension_registration.py`.
  [Apple extension-point identifiers](https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionpointidentifier)
- Android registers `PalladinAutofillService` and releases domain-matched
  datasets only after a Keystore-bound `BiometricPrompt` operation.
- On registration forms, Android offers a 20-character password only for
  explicit `newPassword`/`new-password` hints without a current-password hint.
  iOS 26.2+ implements `ASGeneratePasswordsRequest`; earlier iOS versions use
  the explicit Generate action in the app's Add Credential form. Both paths
  commit encrypted recovery history before returning the password.
- Android accepts `webDomain` only when Android 12+ reports an OS-verified App
  Link for the requesting package and exact host, or when the requester is the
  explicitly allowlisted system Chrome package authenticated by its system-app
  identity. For a native form with no reported domain, the service instead
  obtains that package's exact OS-verified App Link hosts. After biometric
  authentication, a chooser displays each matching Entry and exact domain;
  even one match requires a deliberate choice before one dataset is released.
  The selected domain must belong to the Entry, the original request's verified
  host set, and the current OS authority at handoff, under the cache-generation
  lock. Cancellation/backgrounding clears the chooser's in-memory records.
  This path does not generate passwords or save application associations.
- If an otherwise eligible non-browser native request has no reported domain and
  the OS provides no verified hosts, `MANUAL_NATIVE` is distinct from both `WEB`
  and `VERIFIED_NATIVE`. After biometric authentication the user may search by
  Entry label, username or domain. Selecting a result opens a separate warning
  identifying the unverified request package and selected domain; **Fill once**
  is required to release it. Confirmation binds the Entry/domain to that request
  and is consumed once. It never converts the selected record's host into origin
  authority. Browser exclusion and cache-generation/lease checks run again at
  handoff. No association or search query is persisted; cancellation, background
  and destruction clear in-memory selection. Password generation is unavailable.
- A malformed or ambiguous reported domain never falls back to native hosts.
  Missing browser domains also fail closed: Chrome is explicitly excluded, and
  a package-scoped all-host HTTPS intent capability check excludes other browser
  handlers. A host-specific App Link alone is not browser capability. The probe
  uses a reserved `.invalid` host solely for local intent resolution, never a
  network request; an unavailable capability check fails closed.
- Manifest package visibility includes Chrome plus HTTPS/BROWSABLE handlers
  using an explicit `host="*"` query. A scheme-only query matches browsers but
  misses handlers with concrete App Link hosts, causing the provider UID
  to receive `NameNotFoundException` even when shell inspection shows verified
  links. The wildcard is only a package-visibility capability; every credential
  release still requires exact verified hosts or the separate manual flow.
  See [Android query declarations](https://developer.android.com/training/package-visibility/declaring).
  It does not request
  `QUERY_ALL_PACKAGES`, infer domains from package names, or trust user-selected
  (rather than OS-verified) links.

## iOS manual credential selection

When iOS calls the credential-list extension with **no service identifiers**,
Palladin first authenticates and reads the cache, then offers a searchable list
of credentials. Search examines the in-memory label, username and saved domains;
it never searches passwords or persists the query. Each row shows its domains.
The list warns that the destination is unverified. Selecting a row opens a
separate confirmation showing the selected label and domains; only **Fill once**
releases that credential. Cancellation, an empty authenticated result, or a
replaced request cannot complete a manual fill. Confirmation is bound to a fresh
selection token captured with the displayed credential; replacing a selection
invalidates the earlier confirmation. Host backgrounding (not a temporary
biometric focus change) and genuine controller dismissal invalidate pending
requests, clear the picker, dismiss its confirmation and cancel the extension
request. A later use requires a fresh authenticated request.

This is a deliberate one-operation user authorization, not origin verification.
A nonempty but invalid or mismatched OS identifier list does not enter this
fallback. Existing exact-host matching and QuickType identity selection keep
their domain checks. Manual handoff uses a separate entry point and checks the
same current generation, revocation fence, lease and wall-clock authority under
the same process lock through `completeRequest`. It never derives an expected
destination from the selected credential.

No destination association is remembered. This callback supplies no stable
requesting-app identity when its service-identifier list is empty; a previous
choice must not establish trust for the next unnamed app. Future remembered
associations require an independently supplied stable identity and explicit
user consent. Physical iPhone QA remains required for Safari, associated native
apps, empty-identifier manual selection, cancellation and revocation while the
confirmation is open.

## Provider activation and status

The system provider display name is `Palladin` on Android (all locales) and iOS.

The native provider registrations do not select Palladin for the user. On the
first ready Home screen after setup/unlock, `AutoFillSetupCard` checks the OS and
shows a persistent setup warning until the OS confirms selection. On Android,
it also retains Chrome setup guidance when Chrome explicitly reports that its
third-party AutoFill setting is disabled. There is no
dismissal flag. Its surface, title, description paragraphs and actions reuse
core `SetupCard`, shared with biometric setup; the warning border, platform
guidance and OS activation lifecycle remain owned by AutoFill.
Settings → Security exposes the same card and retains enabled
status. Both refresh on mount and app resume, including returning from system
settings. Opening settings or cancelling the picker never marks setup complete.
Status is selection only, not a promise that a credential cache or biometric
hardware is ready. OS status errors remain visible with retry; no secrets or selection
state are persisted by this flow.

- Android 8+: `AutofillManager.hasEnabledAutofillServices()` checks this app's
  service; a button launches `ACTION_REQUEST_SET_AUTOFILL_SERVICE` with the
  current flavor's package URI. The OS owns selection/consent. Chrome Stable's
  separate readiness is read from its documented
  `AutofillThirdPartyModeContentProvider/autofill_third_party_mode` provider,
  projecting only `autofill_third_party_state`: `0` needs configuration, `1`
  is enabled. Once the OS provider is selected, Home's remaining Chrome card
  offers an explicit `ACTION_APPLICATION_PREFERENCES` intent restricted to
  `com.android.chrome`, with `DEFAULT`, `APP_BROWSER` and `PREFERENCE`
  categories. The user chooses "Autofill using another service" and confirms
  Chrome's restart. Cancelling leaves the warning; mount/resume rechecks the
  reported state. A missing provider, unknown value or failed query never
  claims Chrome readiness or requires users to install Chrome; Settings keeps
  manual guidance. Launch failure keeps the manual route and retry action.
  Existing package visibility is sufficient: the Chrome manifest exports this
  provider without a read permission, so no `READ_USER_DICTIONARY` or broad
  package permission is requested. No browser preference is persisted or
  changed by Palladin. OEM wording (including Samsung One UI) may vary.
- iOS: `ASCredentialIdentityStore.getState` reports whether this provider is
  enabled. On iOS 17+, the button uses the public
  `ASSettingsHelper.openCredentialProviderAppSettings`. On iOS 14–16, manual
  Settings → Passwords → Password Options / AutoFill Passwords instructions and
  a Check again action replace the unavailable public settings shortcut.
  iOS permits multiple enabled providers; the UI intentionally says enabled,
  not that Palladin has become an exclusive default.
- The flow never opens settings automatically, changes the OS default silently,
  or touches credential encryption, cache activation, or provider authentication.

References: [Android provider activation](https://developer.android.com/identity/autofill/autofill-services#request-permission),
[Apple settings helper](https://developer.apple.com/documentation/authenticationservices/assettingshelper),
[Chromium AutoFill integration](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/android_autofill/README.md),
[Chromium provider declaration](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/android/java/AndroidManifest.xml).

## Security contract

1. MK, VK, the user's private key, decrypted vault payloads, plaintext
   passwords, and TOTP seeds never enter App Groups, SharedPreferences, logs,
   analytics, or an unprotected file.
2. Native providers never query the backend directly and never receive the
   user's vault keys.
3. The provider cache stores platform ciphertext encrypted with a dedicated
   random AutoFill key. This key is not derived from MK/VK and is protected by
   Keychain/Keystore with biometric-set invalidation.
4. Cache v2 carries a separately authenticated manifest for the profile,
   organization membership, complete per-Vault access context and finite
   lease, plus each Entry revision/key high-water. Every record is compared
   with that authority; self-consistent substituted records are rejected.
   Cache v1 has no lease or independent authority and is purged, never migrated.
5. Missing, corrupt, stale, expired or clock-rolled-back cache state fails
   closed. Automatic matching rejects ambiguous, mismatched or unverified
   destinations. The explicit absent-domain manual paths on Android and iOS
   authorize only the user-confirmed operation. The durable generation fence includes an
   authenticated maximum observed wall time; rollback over five minutes
   quarantines the generation. A process-lifetime monotonic clock anchor also
   rejects a frozen or slowly advancing wall clock once it trails elapsed time
   by more than five minutes. Android revalidates the requesting package, exact
   domain, generation and lease after biometric authentication and again under
   the revocation lock through the provider response handoff.
6. Logout and account deletion durably revoke access before physical cache,
   key and identity cleanup. A biometric-set change invalidates the platform
   key. Vault lock requires fresh provider authentication before a credential
   can be returned.
7. Plaintext exists only after successful provider or app authentication and
   only long enough to build the OS response, populate an in-memory form, or
   perform an explicit history reveal/copy. Temporary byte buffers are wiped
   where platform APIs expose mutable storage. The in-app copy uses the shared
   timed `SecureClipboard` policy.
8. Domain policy is exact-host only. HTTP(S) URLs may be projected to their
   ASCII host, but userinfo, explicit ports, wildcards, Unicode/confusable
   hosts, malformed labels, parent-domain inference, and `www` equivalence are
   rejected. There is no eTLD, subdomain, or suffix matching.
9. Cache records are bounded to 2,000 records and 16 domains per record; native
   readers reject cache files over 16 MiB. The authenticated platform
   ciphertext contains the manifest and only the record id/bindings, display
   label, username, password, and authorized exact hosts.
10. Generated-password history is separate from the disposable Vault cache.
    Android stores AES-GCM ciphertext in `noBackupFilesDir`; a per-use
    biometric Keystore RSA key unwraps its random history key, and an
    independently authenticated marker binds the active principal.
    iOS stores AES-GCM ciphertext in the flavor-specific App Group with a
    `biometryCurrentSet` Keychain key and active-principal marker. Neither
    provider receives MK, VK, a user private key, or backend access. Every
    history read and mutation checks the active principal against the caller's
    authenticated app account where applicable. On iOS, biometric waiting does
    not hold the revocation lock; the activation token is checked again before
    a history operation commits. Android likewise binds each biometric unwrap
    operation to the activation token and rechecks it under the mutation lock
    before releasing plaintext. The history holds at most 100
    records per account and fails closed at capacity; it never evicts a password
    silently. History remains encrypted across app restart and Vault cache
    rotations. Biometric-set invalidation makes old history inaccessible.

## Generated-password lifecycle

1. On unlock, the app activates a generation session bound to the authenticated
   principal. A fresh app process revokes the old generation session before
   accepting bridge calls. Logout and forced session loss revoke the current
   session using its opaque activation token; a late old revoke cannot remove
   a newer session. A Vault lock leaves the native ciphertext available only
   through a fresh biometric challenge.
2. Android rechecks the exact verified host and requesting package before
   generation and before returning the dataset. It writes the encrypted record
   atomically before the OS response, fills only explicitly marked new-password
   fields (including confirmation when marked), and never overwrites the
   current-password field. iOS uses the system-provided service identifier,
   accepts only exact HTTPS hosts or domain identifiers, applies supported
   password-rule clauses, and rejects unknown or incompatible rules. The iOS
   provider presents explicit Generate and Cancel actions and writes history
   before calling `completeGeneratePasswordRequest`.
3. The app's Security page lists encrypted-history metadata after biometric
   authentication. Reveal and copy are separate authenticated operations;
   reveal hides after 30 seconds or app backgrounding. The user may explicitly
   choose a Vault and open an already-filled Add Credential form, or delete one
   record or clear history after confirmation. Generating from Add Credential
   requires a valid HTTPS URL and saves recovery history before populating the
   form. No OS save callback writes a Vault Entry automatically; Vault save
   remains an explicit user action through the existing encrypted Entry flow.

## Cache lifecycle

1. Unlock synchronizes eligible credentials from server ciphertext using the
   in-memory private key already held by `AuthBloc`. The cache builder reads the
   local MemberIndex first, ignores corrupt/archived/deleted entries, and
   rejects stale revealed revisions. Legacy entries without an explicit
   `autofillDomains` MemberIndex policy remain unavailable until re-projected.
   AutoFill and Dashboard search use the same `MemberIndexPreparationService`
   single-flight operation, so simultaneous unlock listeners cannot start a
   second Vault-list request or a second snapshot chain. Native activation
   has its own session epoch: a foreground/reconnect rebuild queued while
   activation is pending cannot discard the new token. A replacement session
   or revocation still invalidates older activation callbacks. AutoFill awaits that
   complete operation before reading the runtime index, preventing an empty-cache
   race while the first sync is still starting. Offline restart reopens the
   complete persisted policy-2 generation without a network call; an expired
   or disabled offline policy leaves the native candidate set empty.
2. Canonical create, update, restore, delete/archive, and permanent purge, plus
   multi-step import, await successful native cache clearing before sending the
   first remote mutation. Cache clearing awaits native session activation; a
   failed activation or missing token fails closed instead of acknowledging a
   no-op. A failed clear aborts the remote transition. Rebuild
   occurs only after a definitive HTTP result; a final transport failure is
   ambiguous, so the cache remains empty until the next authoritative
   synchronization. Overlapping cache-sensitive mutations form one
   process-local invalidation batch: rebuild waits for every result, and one
   ambiguous result suppresses the whole batch rebuild. Vault create and vault
   delete also rebuild the cache after their definitive mutation. A failed
   rebuild therefore leaves no stale password available to AutoFill.
   SignalR/reconnect invalidation first awaits a durable native deny, then
   repairs the combined Member generation, and only after its current index is
   committed rebuilds the cache locally. A failed deny or rebuild is not marked
   applied; the coalesced invalidation remains queued for retry. Every other
   durable Member sync commit (including an ordinary Entry-list refresh)
   coalesces into the same local-only candidate rebuild after the current index
   publication tail, without starting another sync or per-Entry request.
   Concurrent foreground and durable consumers share an in-flight publication
   only for the same session, commit sequence and complete Vault set. The
   coordinator detaches it on completion and skips already-consumed durable
   updates. A later explicit foreground repair always rebuilds, including after
   native quarantine without a Dart commit. New commits (including refreshed
   leases), native denies and session changes also require a fresh publication;
   the publication record contains no credential or key material.
3. Ordinary vault lock keeps the encrypted cache so AutoFill can operate after
   a fresh OS biometric challenge. The Flutter private key is never copied into
   the native provider.
4. Logout and forced session loss invoke the native revocation path before
   authentication cleanup. Its commit point is an atomically persisted,
   authenticated generation fence; once acknowledged, provider access is denied
   even if later ciphertext/key/identity deletion fails or an OS callback never
   returns. Generation-scoped artifacts and compare-delete cleanup prevent a
   delayed old operation from changing a newer session. After a confirmed fence,
   auth tokens and local key material are cleared in `finally`-style cleanup and
   physical provider cleanup is best effort. If neither revocation nor fallback
   clear can prove a durable deny, interactive logout fails closed without
   claiming success; forced session loss keeps a coalesced bounded retry running
   until a deny is confirmed.
5. A biometric-set change invalidates the platform key. Any failed native read
   durably quarantines the unusable generation before best-effort artifact and
   iOS identity cleanup; the next unlocked synchronization creates a fresh
   dedicated key and cache.

## Android form recognition

Android WebView containers can report `webDomain=""` while their virtual inputs
report the page host. The parser ignores only this exact empty sentinel, just as
it ignores null. Whitespace, malformed nonempty hosts and distinct real hosts
remain in the domain set and fail origin validation. Empty-only browser requests
remain rejected; absent-domain native requests retain the explicit chooser policy.

A reported web host also requires an independently reported HTTPS scheme from
`AssistStructure` (API 28+). Every node reporting a nonempty domain must report
its own HTTPS scheme; a sibling or unrelated node cannot supply that authority.
Only containers with neither domain nor scheme use the empty-sentinel exception.
Missing, unknown or cleartext schemes fail closed;
verified App Links establish host authority, not transport security. Any reported
scheme without a host is an incomplete web context and cannot become native
manual selection. The accepted scheme travels in the explicit immutable
provider authentication intent and is checked again after biometric authentication
and under the existing release lock. Web filling on API 26–27 is unavailable
because those APIs do not expose the scheme. Native forms with neither web host
nor scheme retain their verified-host/manual selection policy.

Login requests may contain a username, a password, or both. Username-first steps
still require the same origin, cache and biometric checks; their response contains
only the recognized username targets. A later password step is a fresh request.
Neither the service nor either authenticated response path requires a password
field on the username step.

The parser reads Android autofill hints/input variations and HTML `input`
`autocomplete` tokens and `type`. Explicit username identifiers (`username`,
`user_name`, `email`, `email_address`, `login`) are supported as native text-field
resource names or HTML text-input `name`/`id`. It does not guess that an arbitrary
text field, search field or preceding sibling is a username. `new-password`
remains a generation-only target; explicit OTP hints take precedence over a masked
password input type so an account password cannot be sent to an OTP field.
Only enabled, visible text-autofill targets are eligible; invisible ancestors
exclude their descendants. Containers are traversed but never targeted themselves;
a disabled container does not suppress an independently enabled child.
HTML hidden, search, non-text, disabled and readonly controls are excluded even
when credential hints conflict. Native filter/search fields are excluded too.
Explicit `confirm_password` / `password_confirmation` identifiers (including
camelCase/hyphen variants), or explicit confirmation hints, cannot receive a saved
password; an explicit
`new-password` hint can make them generation-only targets.

The October 2026 audit compared primary implementations at pinned commits:
[Bitwarden field classification](https://github.com/bitwarden/android/blob/924c851b571d782345bbf5a33d773ca09d826e8a/app/src/main/kotlin/com/x8bit/bitwarden/data/autofill/util/ViewNodeExtensions.kt)
and [login partition selection](https://github.com/bitwarden/android/blob/924c851b571d782345bbf5a33d773ca09d826e8a/app/src/main/kotlin/com/x8bit/bitwarden/data/autofill/parser/AutofillParserImpl.kt)
use HTML/native metadata and permit a username login partition.
[KeePassDX's parser](https://github.com/Kunzisoft/KeePassDX/blob/25493ea30139adab14d937602f28d5243d3f9ecc/app/src/main/java/com/kunzisoft/keepass/credentialprovider/autofill/StructureParser.kt)
also reads HTML semantics and prioritizes OTP, but its login result still requires
a password. Both use broader username heuristics than Palladin. This comparison
informed independent changes; no competitor implementation was copied.

The Bitwarden comparison is pinned to commit
[`924c851b…826e8a`](https://github.com/bitwarden/android/commit/924c851b571d782345bbf5a33d773ca09d826e8a),
not a moving branch. In `ViewNodeExtensions.kt`, `toAutofillView` redirects a
hinted `AUTOFILL_TYPE_NONE` container to a text child, while `isUsernameField`
uses broader identifier/hint terms. Palladin never makes the container itself
a dataset target and classifies eligible children independently. In
`AutofillParserImpl.kt`, the `AutofillView.Login` branch constructs a login
partition without requiring a password view. This supports the username-first
comparison; it is not evidence of Palladin's authentication-result behavior,
which is asserted separately against its real `FillResponse` on the emulator.

JVM parser regressions mock framework input nodes, exercise the production
traversal and assert resulting target IDs. They establish recognition, not OS
presentation or biometric completion. The Android emulator harness separately
exercises system callbacks; Samsung/Chrome/Allegro release behavior remains a
physical-device acceptance check.

## Android dropdown presentation

Unlock and generated-password actions use a branded RemoteViews row with a
24dp shield and a localized bold label. Authenticated credential choices follow
the extension hierarchy: username first (14sp bold), optional Entry label (12sp,
omitted when redundant with username/host), exact selected host (11sp). They use
no per-credential icon and add no Vault name because the cache has none. Rows have
65dp minimum height, 9dp vertical/10dp horizontal padding, an 11dp corner radius
and a subtle border; each line ellipsizes independently. Explicit paired day/night
colors avoid host-dependent system text styles. Native AutoFill owns the popup
container and spacing. This is a fill-only action, without automatic submission.
Credential labels/usernames remain visible only in the authenticated picker.
Verify readable rows and password as well as username filling on the device;
resource compilation does not establish actual Chrome/keyboard rendering.

## Android keyboard action

On Android 11+, a compatible keyboard may show the localized unlock/generate
action inline. The service uses AndroidX Autofill 1.3.0's standard v1 UI template
with the first IME presentation spec (including its size/style). A missing request,
zero suggestion capacity or unsupported template retains the dropdown. Selecting
the chip invokes the same biometric authentication activity; long-press attribution
opens Palladin through a fixed value-free PendingIntent. Origin/cache gates run
before any presentation is constructed. No credential value enters this chip.

Reference: [Android inline autofill guide](https://developer.android.com/identity/autofill/ime-autofill).
Android API compilation checks the platform/AndroidX calls. Actual keyboard rendering, selection and fallback on
Samsung Keyboard/Gboard remain physical-device QA, not proven by these tests.

## Android last-request diagnosis

While the production service is alive, authorized adb users can inspect its last
request without collecting credential or form values:

```sh
adb shell dumpsys activity service io.palladin.mobile/io.palladin.mobile.autofill.PalladinAutofillService
```

The service emits only fixed keys with enums, counts and booleans: request result,
password count, reported-domain cardinality (zero/one/ambiguous), package
presence, origin verification status, generation-session/cache availability and
inline-request presence. `NOT_CHECKED` means the existing short circuit skipped
that operation; diagnostics never read cache/history just to populate a field.
`QUERY_UNAVAILABLE` also covers Android versions before App Link verification.
`CHECKING` means the request did not reach a recorded terminal result. An offered
response with an unverified/unavailable origin may open the explicit manual
native confirmation flow; it does not assert verified origin. Inline
request presence does not imply the response includes an inline presentation.

Only one snapshot exists in service memory. Each request replaces it; service or
process destruction discards it. No package/domain strings, field identifiers,
credentials, structures, exception messages or history are retained or logged.
The surrounding system `dumpsys` output is owned by Android, not this snapshot.

Access uses the existing Android framework boundary, with no new exported IPC:
[Android 16 ActivityManagerService.doDump](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/services/core/java/com/android/server/am/ActivityManagerService.java)
checks `DumpUtils.checkDumpAndUsageStatsPermission` before service dispatch.
[ActivityThread](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/core/java/android/app/ActivityThread.java)
posts the protected service dump to the app main thread, so Binder caller identity
must not be reinterpreted there as the original shell caller. Physical-device
verification of this command and the actual rejection remains required.

## Required device QA

- Android (include Samsung Galaxy S22 Ultra): on a fresh install, verify the
  Home warning and Security status, cancel the system picker and confirm the
  warning remains, then select Palladin and return to confirm the Chrome step
  remains when its third-party mode is disabled. Open Chrome settings from that step, cancel
  and verify it remains, then enable the setting and restart Chrome; resume
  Palladin and verify the warning disappears.
  Disable Palladin in OS settings and resume to confirm the OS setup step returns.
  Verify unsupported Chrome versions and query failures do not falsely claim
  Chrome readiness or block users of other supported applications.
  Then verify biometric success/cancel/failure, stale-cache mutation, logout
  wipe, and biometric enrollment change. Also verify registration forms with
  new-password and confirmation hints, unrelated current-password forms,
  unverified native packages, interrupted sign-up recovery after restart,
  history capacity, explicit Vault save, and session/account switching.
- iOS: verify setup status, settings navigation on iOS 17+, manual instructions
  on iOS 14–16, cancel/enable/disable and resume. Verify Safari login form,
  identity selection, biometric success/cancel/failure,
  stale-cache mutation test, logout wipe, biometric enrollment change. On iOS
  26.2+, verify generation requests with and without site rules and recovery
  after restart; on older iOS verify the explicit in-app Generate path. Verify
  manual Vault save and account switching on physical iPhones.
- Native Android application forms without `webDomain`: verify an OS-linked
  application with multiple exact verified hosts, deliberate Entry/domain
  selection, cancel/background, and revocation while the chooser is open.
  Malformed/ambiguous/unverified reported domains and browsers without a page
  domain must return none. A non-browser package with no domain or verified host
  must require the separate manual warning and one-operation confirmation. Check package visibility from the provider UID.
- JVM tests exercise origin resolution, exact selection bindings and existing
  cache/lease/revocation rules; Android API compilation checks native call sites.
  They do not instantiate the system AssistStructure, biometric UI or chooser,
  and do not prove the actual Allegro device flow. Manual-mode QA must additionally
  verify search, explicit warning/Fill once, cancel, backgrounding, a lease or
  generation change before confirmation, and that a repeated confirmation cannot
  release again. A nonempty unverified web domain must never reach this mode.
- Automated Flutter/native tests and simulator builds do not replace physical
  device QA. Record Chrome/Safari background and locked-app behavior,
  biometric-set changes, corrupt-cache recovery, and Vault v2 delta refresh on
  real Android and iOS devices before release sign-off.

## Native files

- iOS provider: `ios/CredentialProvider/`
- Android provider:
  `android/app/src/main/kotlin/io/palladin/mobile/autofill/`
- Android service config: `android/app/src/main/res/xml/autofill_service.xml`
