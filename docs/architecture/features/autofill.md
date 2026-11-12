# System AutoFill

## Current state

- The app and native providers read the canonical encrypted Member database.
  There is no dedicated plaintext credential export or bulk password-rebuild step.
  MemberIndex supplies eligible metadata; only a selected MemberSecret is opened.
  AutoFill eligibility requires explicit exact domains, current Entry/key versions,
  independently authenticated Vault context and a finite valid lease.
- Android registers `PalladinAutofillService`; iOS embeds an
  `ASCredentialProviderExtension`. Each OS request must authenticate through
  password unlock or optional protected biometric unlock. An unlocked app alone
  does not authorize an arbitrary provider request.
- iOS uses `com.apple.authentication-services-credential-provider-ui` and the
  `ProvidesPasswords` capability. Identity-store entries are suggestions, never
  credential authority. See `tool/tests/test_ios_extension_registration.py` and
  [Apple extension registration](https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionpointidentifier).
- On registration forms, Android offers a 20-character password only for
  explicit `newPassword`/`new-password` hints without a current-password hint.
  iOS 26.2+ implements `ASGeneratePasswordsRequest`; earlier iOS versions use
  the explicit Generate action in the app's Add Credential form. Both paths
  commit encrypted recovery history before returning the password.
- Android treats `webDomain` as verified only when Android 12+ reports an OS-verified App
  Link for the requesting package and exact host, or when the requester is the
  explicitly allowlisted system Chrome package authenticated by its system-app
  identity, or the exact credential delegation described below. The separate
  MANUAL_WEB consent path below does not verify the claimed domain. For a native form with no reported domain, the service instead
  obtains that package's exact OS-verified App Link hosts. After request
  authentication, a chooser displays each matching Entry and exact domain;
  even one match requires a deliberate choice before one dataset is released.
  The selected domain must belong to the Entry, the original request's verified
  host set, and the current OS authority at handoff, under the source
  handoff lock. Cancellation/backgrounding clears the chooser's in-memory records.
  This path does not generate passwords or save application associations.
- If an otherwise eligible non-browser native request has no reported domain and
  the OS provides no verified hosts, `MANUAL_NATIVE` is distinct from both `WEB`
  and `VERIFIED_NATIVE`. After request authentication the user chooses a current Entry by
  label and exact host. Selecting a result opens a separate unverified-destination
  warning showing the selected Entry and host; **Fill once**
  is required to release it. Confirmation binds the Entry/domain to that request
  and is consumed once. It never converts the selected record's host into origin
  authority. Browser exclusion and source-epoch/lease checks run again at
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

## Home search attachment

Repeated Home mounts share completed search preparation within the current
unlocked principal and lock epoch. Each mounted search cubit still queries the
current index; no query results, index snapshot or key is cached by this gate.
Failure permits retry. Authoritative unlock/resume/reconnect/mutation preparation
remains separate and can refresh ciphertext even after Home preparation completes.
Direct unlocked-session replacement first clears search state, the Vault list and
shared Member index preparation, then prepares active search views with the new
session. Old in-flight work cannot become the new session's completed preparation.

## Shared source synchronization

The previous v2/v3 credential catalogs are retired for credential fill. Their
migration/cleanup and separate save/history primitives must not be mistaken for
the active credential source. The canonical Member snapshot/delta protocol owns
ciphertext synchronization; changing one Entry does not export all passwords.

`AutoFillSourceAccessService` coordinates durable source denial, current profile
and claims, pending mutation owners and source epochs. `AutoFillSourcePreparationService`
activates reconciled metadata without opening credential bodies. Local writes and
remote invalidations deny before changing the source; only authoritative completed
repair can release its own owners. Overlapping or uncertain work stays denied.

Provider authentication and source epochs are separate. A routine ciphertext update
invalidates a selected plaintext result, but does not erase the original request's
one-operation authentication. Final handoff checks the captured selected epoch,
request identity and original destination again. Lock, revoke, logout and account
replacement cancel authorization. Async completion from an old account cannot
modify or activate the replacement source.

The loopback benchmark `tool/member-preparation-benchmark/main.dart` uses real
SQLite, transport and crypto: 160 metadata candidates open zero secret bodies;
one selected credential opens one body with no extra HTTP. This measures the
source path, not OS/IME or physical biometric latency.

## Android native authentication handoff

On Android 12/API 31+, native requests offer one locked Dataset with null values,
the existing branded unlock presentation and the existing immutable explicit
PendingIntent. After authentication and the request picker/required confirmation,
Palladin returns only the selected Dataset. The system fills the original target
IDs directly; there is no second credential choice in the keyboard. The returned
Intent sets `EXTRA_AUTHENTICATION_RESULT_EPHEMERAL_DATASET=true`, so Android retains
the locked initial dataset instead of caching an unauthenticated credential choice.
Clearing and filling again requires fresh request authentication and a new selection. Every final
origin, generation, lease, revocation and one-operation confirmation check remains
under the existing mutation lock through `setResult`.

API 26–30 retain the previous response-authentication flow because they do not
provide the explicit ephemeral-result contract. Web requests (which can return
multiple matched entries) and password generation also retain response-level
authentication. SaveInfo and its client state remain on the initial FillResponse;
a Dataset result does not replace them. No platform-provided fill-in extras are
trusted: the immutable intent already carries the original IDs and origin context.

This uses the public [Dataset authentication contract](https://developer.android.com/reference/android/service/autofill/Dataset.Builder#setAuthentication(android.content.IntentSender))
and [API 31 ephemeral result](https://developer.android.com/reference/android/view/autofill/AutofillManager#EXTRA_AUTHENTICATION_RESULT_EPHEMERAL_DATASET).
Bitwarden's pinned [initial authenticated dataset](https://github.com/bitwarden/android/blob/924c851b571d782345bbf5a33d773ca09d826e8a/app/src/main/kotlin/com/x8bit/bitwarden/data/autofill/util/FilledDataExtensions.kt)
and [selected Dataset completion](https://github.com/bitwarden/android/blob/924c851b571d782345bbf5a33d773ca09d826e8a/app/src/main/kotlin/com/x8bit/bitwarden/data/autofill/manager/AutofillCompletionManagerImpl.kt)
provide precedent for the public flow, not Palladin's origin or ephemeral policy.
The change removes dependence on redisplaying a second suggestion after an
explicit native selection; it does not claim to repair IME rendering failures.

Native request invalidation clears Flutter's local capability without echoing a
second cancellation command. The native owner has already ended that request;
replaying cancellation could background the app while a replacement is opening.
Explicit user cancellation, expiry and background cancellation retain their
native cancellation boundary. Incoming requests are not treated as presented
until the main activity resumes: the delayed hidden/stopped events during the
external authentication activity's handoff cannot cancel the incoming request.
After presentation, leaving the main activity still cancels that exact request;
replacement, expiry, lock and revocation retain their independent fences.

## Physical preparation timing (2026-11-06)

On S22 Debug29, the Binance attempt spent about 3.0 seconds inside picker
preparation; candidate metadata reading took 14 ms. Value-free HTTP classification
showed one Vault-list request (1,944 ms) and two overlapping delta requests for
two Vaults, with no snapshot or duplicate list/sync pass. Preparation completed
264 ms after the last delta response. These are one-device observations, not a
CPU profile or a general latency guarantee. They identify network freshness
repair as the dominant observed wait; they do not justify skipping authority,
lease or revoke checks. Concurrent foreground preparation and picker reads
already share the active MemberIndex preparation; later freshness requests may
require a trailing pass to preserve mutation/reconnect correctness.

## Generic native field recognition

`CredentialFieldIds` uses a finite `Matched(role)` / `Unknown` / `Rejected`
sequence, without package-specific branches. Platform roles take precedence over
structural and complete-label fallbacks; rejected eligibility or purpose never
falls through. Structural inference requires one current-password target, one
unknown editable **text** field under the same direct parent and no other editable
field anywhere in the request or registration role. Numeric, phone and masked-PIN fields count toward
ambiguity but cannot become inferred usernames.

Complete native labels are an auxiliary finite EN/PL fallback, not universal
language recognition. Their normalization follows the pinned extension
[complete-label rules](https://github.com/Palladin-io/palladin-browser-extension/blob/b992d0ea64d9727078619999f682d3cfff650c33/src/content/isolated/control-labels.ts):
bounded own metadata, whole labels and one unambiguous candidate; no arbitrary
substring or nearby-label scan. Unknown languages and absent OS callbacks remain
limitations. API34 typed datasets require separate runtime evidence and are not
part of this implementation.

A manually requested native form with one focused unknown text target and no
recognized credential, registration or excluded credential targets can enter a
separate username-only path. WEB/browser requests are excluded. The manual flag
is not proof of human intent: app code can request Autofill. After authentication,
the provider therefore requires its own username-only confirmation even for an
OS-verified native app. That one-shot choice binds the original username ID,
Entry, exact domain and requesting package. Final origin, generation, lease and
revocation checks remain mandatory. Passwords are stripped before retaining
chooser records and never included in this path's dataset or Intent. The shared source lists metadata and opens only the explicitly selected credential;
the username-only result never includes a password.

Regression provenance: Allegro is user-confirmed working and is not patched.
Binance remains blocked on a physical trace; no guessed fixture is provided.
iFirma's test is **synthetic metadata, not a captured AssistStructure**: static
inspection of version 3.1.16 (5094), package `pl.ifirma.ifirmafaktury`, found
“Adres e-mail lub login” in its Hermes bundle and the React Native path
`ReactTextInputManager.setPlaceholder` → `ReactEditText.setPlaceholder` →
`TextView.setHint`. [Android TextView](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/java/android/widget/TextView.java)
copies hints into `onProvideStructure`. This proves the metadata channel, not the
live form's props, types, origin or callback. The native harness covers this
plain-text/no-autofill-hint case, opaque labels next to a password, explicit
username-only confirmation for verified/unverified native sources, cancellation
and rejected WEB/password targets. Real iFirma compatibility remains unverified.

A later physical metadata-only trace of iFirma build 5094 captured explicit
`username` and `password` hints with native input types 33 and 129, plus a disabled
extra text field. Both are recognized by the unchanged parser. The reduced
[observed fixture](../../../tool/android-autofill-harness/observed-ifirma.md)
distinguishes this evidence from the earlier placeholder-only synthetic test;
it does not prove release-provider callback or successful UI/fill on the phone.

The inspected APK SHA-256 is
`8ee4e3b13437f7930759f093e329bc8e746a7c234411662e46db7c17e7a94715`;
its signer SHA-256
`ea5d01274bd745e47af9784222c755cc319a6a3f72e8137417b540324797b07e`
was verified against first-party [asset links](https://www.ifirma.pl/.well-known/assetlinks.json).
Public download metadata: `https://d.apkpure.net/b/XAPK/pl.ifirma.ifirmafaktury?version=latest`.
No APK is redistributed.

## iOS service matching

Credential lists, QuickType identity selection and the final handoff validate
Apple's service identifier type before projecting its exact host. A URL identifier
must explicitly use HTTPS. A domain identifier must contain only a valid host;
it conveys the OS-provided domain, not evidence of native-app HTTPS transport.
An HTTP, malformed or type-inconsistent identifier rejects the whole nonempty
list, even alongside a valid matching domain. Empty lists retain the separate
manual confirmation flow below. Cache host normalization is not transport
authority and cannot override this request check.

Apple owns field recognition and credential routing. Username-first forms need
appropriate username/password content types on their separate destination
screens; the provider returns an `ASPasswordCredential` containing both values.
See [Apple's multipage form guidance](https://developer.apple.com/documentation/security/enabling-password-autofill-on-a-text-input-view).
Tests cover matching and the final lease guard, not real Binance/iFirma behavior
or OS field routing; those require device QA.

## iOS manual credential selection

When iOS calls the credential-list extension with **no service identifiers**,
Palladin first authenticates and reads current Member metadata, then offers a searchable list
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

## Preparation feedback

Home no longer shows a bulk password preparation component or recurring 0/0
progress. Normal dashboard content and optional provider/biometric setup remain.
The request UI owns loading, authentication, selection and recoverable errors.
Selecting Palladin in OS settings enables routing; it is separate from having a
current encrypted Member source and authorization for the requested credential.
Backgrounding cancels sensitive request UI; it does not delete the canonical
ciphertext or require a fresh full password export on the next unlock.

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
hardware is ready. A failed settings launch preserves the last OS-reported
selection and offers platform-specific manual instructions plus another explicit
launch attempt; it never marks setup complete. Setup has no dependency on cache
preparation, and EN/PL Android/iOS tests run with only the settings bridge. OS status errors remain visible with retry; no secrets or selection
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
- Browser scope is separate from provider selection: current Android web-origin
  verification explicitly supports the authenticated system Chrome package.
  Selecting Palladin does not imply every Android browser is supported. Chrome's
  third-party-mode check is a setup hint, never origin authority. iOS Password
  AutoFill uses the credential provider in Safari and other participating apps;
  it does not require installing the desktop browser extension. Other browsers
  still depend on their OS integration and the existing exact-service checks.
- The flow never opens settings automatically, changes the OS default silently,
  or touches credential encryption, source activation, or provider authentication.

References: [Android provider activation](https://developer.android.com/identity/autofill/autofill-services#request-permission),
[Apple settings helper](https://developer.apple.com/documentation/authenticationservices/assettingshelper),
[Chromium AutoFill integration](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/android_autofill/README.md),
[Chromium provider declaration](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/android/java/AndroidManifest.xml).

## Security contract

1. The server never receives plaintext credentials or keys. Plaintext keys remain
   in process memory. The explicit approved exception is a local encrypted MK
   envelope protected by platform biometric key access; see [unlock](unlock.md).
2. Providers do not fetch Vault data from the backend. They open the same canonical
   ciphertext using independently authenticated profile, claims, KDF configuration,
   Vault bindings, revisions and original finite leases. Metadata alone never
   authorizes secret release.
3. Password or biometric authentication is bound to the original OS request. Native
   final handoff checks exact destination, original field IDs, current source epoch,
   expiry and revocation. Routine source updates cannot extend authentication TTL.
4. Missing, corrupt, expired, quarantined, mismatched or rolled-back authority fails
   closed. Explicit absent-domain manual selection remains a separately confirmed
   one-operation path, never a persistent package/domain association.
5. Ordinary Vault lock clears live app keys and request state but retains encrypted
   source data. Logout/account loss durably denies the source before cleanup.
   Async old-session work cannot reopen a replacement account.
6. Selected plaintext exists only during the request callback/OS handoff. Mutable
   key buffers are wiped where APIs permit. No credentials, keys or search terms
   enter logs, analytics, Intent extras or intermediate persistent bridge storage.
7. Destination policy is exact-host only. Incoming URL requests require HTTPS;
   stored host normalization is not transport authority. No eTLD, sibling-domain,
   suffix or `www` equivalence authorizes fill. Native packages require independently
   verified association or the distinct explicit manual flow described below.
8. Generated-password history and explicit save have independent scoped authority,
   encryption and retention. They are not removed by retirement of the bulk fill
   catalog. Their platform protection and consent contracts remain separate.

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

## Encrypted source lifecycle

1. Unlock/reconnect synchronize canonical encrypted Member data through the shared
   preparation operation. Metadata activation follows committed current data;
   it does not reveal each password. A request reads candidates and opens only
   its selected Entry under the original lease and current source ticket.
2. A genuine connection failure can use the protected local account projection and
   canonical offline generation. HTTP authorization errors, schema failures, disabled
   offline policy or expired leases cannot take that fallback. Pending remote
   invalidation is not completed by stale offline data.
3. Local mutations and remote invalidations acquire durable deny ownership before
   source changes. Definitive authoritative repair completes only covered owners.
   Unknown transport results and overlapping mutations remain denied until repaired.
   Database opening/migration captures session identity before asynchronous work.
4. Ordinary lock preserves ciphertext and the source account session. It cancels
   requests and clears app plaintext. A later request authenticates independently;
   no full export is needed. Cold ACTIVE-source adoption requires exact profile,
   claims and encrypted account/KDF equality; quarantined/revoked/legacy state is
   not promoted by that optimization.
5. Account replacement/final auth loss synchronously fences callbacks and admits
   durable native denial. New bootstrap waits behind that barrier. A failed denial
   blocks bootstrap. AuthLoading and ordinary Vault locks are not account changes.
   Accepted token replacement compares canonical principal/organization/membership/
   offline-policy claims before secure-storage writes. Changed or unknown claims
   require durable source transition first; expiry-only refresh preserves the
   source. New bootstrap reads the new authority after token serialization ends.
   A concurrent logout/login cancels an obsolete pending token write.
6. During biometric enrollment/migration, OS resume skips redundant foreground
   source repair. Real invalidation/revoke still proceeds. A counter covers the
   entire asynchronous biometric mutation and is released on success or failure.

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
provider authentication intent and is checked again after request authentication
and under the existing release lock. Web filling on API 26–27 is unavailable
because those APIs do not expose the scheme. Native forms with neither web host
nor scheme retain their verified-host/manual selection policy.

Login requests may contain a username, a password, or both. Username-first steps
still require the same origin, source and request-authentication checks; their response contains
only the recognized username targets. A later password step is a fresh request.
Neither the service nor either authenticated response path requires a password
field on the username step.

The parser reads Android autofill hints/input variations and HTML `input`
`autocomplete` tokens and `type`. Explicit username identifiers (`username`,
`user_name`, `email`, `email_address`, `login`) are supported as native text-field
resource names or HTML text-input `name`/`id`. Native structural inference is
limited to one current-password target and one otherwise unknown editable text
field under the same direct parent, without extra editable fields or registration
roles. A finite complete-label fallback is auxiliary; it does not use arbitrary
substrings. An unknown focused native text field can be selected only through the
separate manually requested, provider-confirmed username-only path above. Search,
OTP and other terminally rejected targets cannot enter these fallbacks. `new-password`
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
a decorative 24dp Palladin brand logo, without website-specific icons or Vault
names in the system presentation. Credential rows have
65dp minimum height, 12dp vertical/14dp horizontal padding, an 11dp corner radius
and a subtle border; each line ellipsizes independently. Explicit paired day/night
colors avoid host-dependent system text styles. Native AutoFill owns the popup
container and spacing. This is a fill-only action, without automatic submission.
Credential labels/usernames remain visible only in the authenticated picker.
Verify readable rows and password as well as username filling on the device;
resource compilation does not establish actual Chrome/keyboard rendering. The
debug harness renders real resources in EN/PL and light/dark at 130% font scale,
checks exact content, ellipsis and decorative-logo accessibility, and captures
screenshots. Physical Gboard/Samsung and TalkBack checks remain required.

## Android keyboard action

On Android 11+, a compatible keyboard may show the localized unlock/generate
action inline. The service uses AndroidX Autofill 1.3.0's standard v1 UI template
with the existing Palladin logo in the public start-icon slot (original colors),
a localized title/accessibility description, and the first IME presentation spec
(including its size/style). The IME controls appearance and may ignore inline
suggestions; the branded RemoteViews fallback remains available. A missing request,
zero suggestion capacity or unsupported template retains the dropdown. Selecting
the chip invokes the same request authentication activity; long-press attribution
opens Palladin through a fixed value-free PendingIntent. Origin/source gates run
before any presentation is constructed. No credential value enters this chip.

After request authentication and the existing origin/session checks, both web
and native credential datasets retain optional inline presentation. The original
IME's specs and capacity are copied as value-free metadata into Palladin's explicit,
immutable authentication PendingIntent. No IME token/package/extras are copied.
The 32-spec bound protects this bridge; larger spec lists fall back entirely
to RemoteViews. A dataset uses its original position's supported v1 spec; the last
spec is reused for further positions only within the IME capacity, as required by
[`InlineSuggestionsRequest`](https://developer.android.com/reference/android/view/inputmethod/InlineSuggestionsRequest#getInlinePresentationSpecs()).
Unsupported, missing, malformed and pre-Android-11 metadata leave the branded
dropdown intact. No field classification, origin, biometric or lease gate changes.

Authenticated inline content uses username as title, exact host as subtitle and
the existing Palladin logo. EN/PL accessibility text also includes the Entry label;
the full username/label/host hierarchy remains in RemoteViews because v1 has only
two text slots. No credential appears in the pre-authentication unlock chip.
The IME can suppress or restyle inline suggestions. This capability improvement
is not a diagnosis or proof of a fix for intermittent system dropdown disappearance.

Reference: [Android inline autofill guide](https://developer.android.com/identity/autofill/ime-autofill).
Android API compilation checks the platform/AndroidX calls. Actual keyboard rendering, selection and fallback on
Samsung Keyboard/Gboard remain physical-device QA, not proven by these tests.

## Foreground source repair recovery

Durable Member updates coalesce metadata-source activation for the current unlocked
session. Retry timers retain no keys, stop on session change and cannot release
another mutation's deny ownership. Failed activation remains unavailable until a
valid repair; it never falls back to a retired credential catalog. Source activation
is not evidence that every third-party form emits an OS AutoFill request.

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

## Explicit iOS password saving

See [iOS explicit password save](ios-explicit-password-save.md) for the iOS 26.2+
consented encrypted handoff, shared Flutter confirmation and older-iOS fallback.

## Explicit Android login saving

Android 9+ attaches `SaveInfo` only to an unambiguous username/password pair
with independently verified source authority and an existing process-local
Palladin login session. This save-only response does not require a populated
provider cache. Both selected fields must still exist in the same final
AssistStructure/form; multi-step logins whose username field disappears are
not supported. Authenticated fill responses retain that same request's
`SaveInfo`. Android 8 does not offer this deferred flow.

Web fields must inherit the exact HTTPS host they claim; a sibling node's
origin cannot authorize capture. Native forms use only the package's exact
OS-verified App Link hosts, with an explicit host choice in the confirmation
page; that association does not claim HTTPS transport. Unknown native origins,
multiple passwords, confirmation-only passwords, OTPs and ambiguous sources
are not eligible. Capture compares the original field IDs, source mode, host,
scheme, requesting package and current signing certificates, and reads only
bounded `autofillValue` text.

`onSaveRequest` retains one bounded, expiring RAM capture. Android receives only
an opaque identifier through an immutable, one-shot `PendingIntent` supplied
to `SaveCallback.onSuccess(IntentSender)`. No plaintext enters Intent extras,
saved instance state, URLs, files, history, logs or analytics. Replacement,
expiry and process death invalidate the capture. Account logout/replacement
revokes the independent login authority; ordinary Vault lock retains only that
non-secret authority so the same login can unlock before consuming the draft.

After that unlock, a separate MethodChannel consumes the capture once and
revalidates package identity and origin. The disposable Flutter confirmation
shows the source, offers the shared `ChooseEntryVaultSheet`, and writes nothing
until Save. Backgrounding or locking after presentation clears controllers and
cancels the operation. Saving reuses canonical on-device Credential encryption,
with private-key/session generation checks across Vault loading, crypto, cache
invalidation, token lookup and retries. Source validation runs again after
cache invalidation and token lookup, including the 401 retry. This is the last
available native authority check, not an atomic transaction with Android
package state and the server. Cache invalidation failure blocks the write. A request already accepted
by the server cannot be undone by a later lock; stale UI and retries are
suppressed. No existing Entry is silently updated and no app association is
remembered.

The native JVM tests cover field/source continuity and RAM mailbox invalidation;
Flutter tests cover explicit confirmation and session guards, including a real
loopback 401 refresh race. They do not constitute physical-device OS save UI
acceptance. The Android save trigger, deferred app launch and unlocked
confirmation must also be exercised on a synthetic device fixture before release.

### Android debug identity

Android debug builds use `Palladin (Debug)` for the launcher and system AutoFill provider label. English and Polish unlock, biometric and generation prompts also identify the debug build, including the public inline suggestion and dropdown paths. These resources live only in `src/debug`; release labels remain unchanged. The label does not select a backend environment.


### Exact-host credential delegation for app WebViews

On API 31+, a recognized current-credential form in a non-browser app may report
an HTTPS host absent from that package's OS App Links. Credential fill can use a
direct `https://<exact-host>/.well-known/assetlinks.json` statement containing
`delegate_permission/common.get_login_creds`, `android_app`, the exact package,
and every current installed APK signing certificate. Historical signer lineage,
sibling/root domains, `handle_all_urls` alone and transitive `include` statements
do not supply this authority. Existing OS/browser checks remain first; disabled
link handling and failed OS association queries are not overridden. A successful
null OS result means the package declares no HTTP/HTTPS App Links; it is unverified,
not a query failure, so independent exact-host credential delegation may still be
checked. Null never authorizes fill by itself. A missing system service or thrown
query remains denied even with a cached proof. Save/generation still require OS
authority. Native manual selection, password generation and SaveInfo/save authorization are unchanged.

The request runs off the UI thread. Its three-second deadline includes queue and
DNS time; two workers and two queued requests bound stuck platform DNS calls.
Cancellation/timeout removes queued work, cancels HTTP and permits exactly one
completion. Late success cannot publish a proof. OkHttp receives only the resolved
public IP addresses checked for that exact hostname, avoiding a second DNS lookup.
TLS hostname/trust validation stays with the library/platform. No redirects,
proxies, cookies, authorization headers, response disk cache, logging or intermediary
lookup service are used. Only status 200, application/json, identity encoding and
at most 64 KiB of strict UTF-8 JSON are accepted. Duplicate keys, malformed JSON,
mixed include/authority statements and excessive structure fail closed. Standalone
include statements are ignored without fetching; unrelated bounded JSON metadata
is permitted but cannot supply authority.

A maximum of 32 positive proofs lives only in process memory, for 60 seconds of
monotonic time. Its key is exact host/package/current signer set. Before authentication
entry and final credential handoff the app reads the current installed identity,
checks the proof lifetime and OS policy again, and retains current source epoch,
lease, lock/revoke and exact credential-domain checks. An expired proof cancels the
operation rather than performing UI-thread networking or silently extending authority.
Private/special-use destinations, including NAT64/transition prefixes, are rejected;
offline operation needs existing OS authority or a still-valid memory proof.

Primary contracts: [Google credential-sharing setup](https://developers.google.com/identity/credential-sharing/set-up)
and [DAL consumers and principals](https://developers.google.com/identity/credential-sharing/digital-asset-links).
The observed Binance case and counterfactual regressions are documented in
[`observed-binance.md`](../../../tool/android-autofill-harness/observed-binance.md).

OkHttp is pinned to 5.5.1, whose security update blocks compromised eMudhra
intermediates. Its Android artifact requires compileSdk 37; target/min SDK remain
unchanged. Existing AGP 8.11.1 emits an unsupported-compile-SDK warning (not
suppressed); successful compilation/runtime evidence is required before release.
The unit harness loads only the real Android 14 streaming-reader classes from a
pinned test-only android-all artifact, ahead of throwing SDK stubs. These classes
are not compiled into the provider/application APK; strict parser tests execute
actual reader methods and do not mock parsing.


App-embedded WebViews on API31+ use the same locked, null-valued dataset
presentation and ephemeral selected-Dataset handoff as native app fields. A
same-WebView emulator comparison showed response-level authentication produced
no initial inline row while dataset-level authentication rendered the unlock
chip. This is separate from the missing DAL origin authority. After authentication,
the existing picker shows only records matching the original exact reported WEB
host; it never substitutes OS native domains or a manual unknown-origin choice.
The original immutable Intent binds the expected authentication result shape.
The final selection rechecks that WEB authority and generation/lease/revoke state
inside the existing handoff lock. Browser/Chrome, API26–30, generation and save
contracts retain their prior response/authority paths.

The iOS app registers the shared Member-source control API on
`io.palladin.mobile/autofill-request`, matching the Dart source controller and
protected configuration reader. The legacy `io.palladin.mobile/autofill`
channel remains registered to the **same plugin and source-fence instance** for
existing save/history and retirement callers. The executable simulator test
`tool/test_ios_member_registration.sh` exercises registration and encoded calls
through both channels; it requires `FLUTTER_ROOT` and a booted iOS simulator.

An independently authenticated iOS bootstrap may send `forceQuarantine: false`
to preserve an already ACTIVE source only when its profile binding, complete
claims and canonical encrypted account configuration are unchanged. Omitted flags
default to quarantine; malformed flags fail. Every begin still rotates the
session/epoch, so an existing provider request cannot adopt the new authority.
Quarantined/revoked sources and changed bindings remain quarantined. Activation
of an already ACTIVE exact registered app ticket is an idempotent acknowledgement;
it does not rewrite authority or extend any original Vault lease. Mutation and
security-repair owners must request quarantine before changing the shared DB.

The Android request host reads the app-owned AuthBloc from BlocProvider.
AuthBloc is factory-registered in DI; resolving it again would create an
unauthenticated session and silently prevent the picker from opening. The
host regression uses the production factory lifetime and verifies cold/warm
requests, unlock continuation, and cancellation on leaving the presented flow.

The picker uses the same AppScreen.titled / ListScreenHeader, Entry count,
scrolling AppSearchField, skeleton and card/list spacing as Global Entries.
There is no separate Material AppBar; a header close action cancels selection.
EntryListCard is reused in selection mode. A single
verified host prepopulates the text filter; manual-native requests have no
invented trusted search origin. Editing/clearing search never expands the native
verified host set. Rows contain metadata only; no reveal/edit controls are
shown, and selecting a row still performs the guarded selected-body read.
Source changes before request authorization clear stale state without falsely
claiming a fill failure; post-authorization invalidation still fences selection.
The authenticated picker uses AppEmptyState for no eligible logins and separately
for a search with no results. Clearing search filters only the already-authorized
candidates; it cannot expand the original request's verified hosts. Loading and
failed preparation never appear as an empty result. Both states are localized.

Product-owner decision 2026-11-05: an already unlocked app authorizes a new
Android request through its live verified session, without another KDF/biometric
prompt. The host captures the current app-owned principal and private-key object
identity, verifies unlocked state before/after async authorization, and mints only
a request-bound native capability for the bound source session. There is no new
persisted grant or key. Lock/logout/key or account replacement and process death
remove this authority. A locked app still uses its existing unlock screen once;
manual-native and username-only selections retain explicit one-operation consent; the Android picker row tap grants it after the visible notice (2026-11-09 decision).

While candidates are being read, source invalidation clears stale rows and may
trigger at most one coalesced metadata recovery per request. A further change
after recovery starts requires explicit Retry; there is no timer or unbounded
full-preparation loop. Lock, expiry, revoke and request replacement never reload.

The Android host observes the application's GoRouter delegate and waits for
the destination Navigator frame after `/unlock` redirects before pushing its
picker. Otherwise the router removes that pageless route with the outgoing
unlock page and its completion incorrectly cancels AutoFill. This is a route
readiness gate, not a delay or reopening after Back; lock and user cancellation
still terminate the original request. A real-GoRouter regression covers both
successful redirect and lock while redirect completion is pending.

The pre-authorization dropdown/inline action reads “Fill with Palladin.io” /
“Uzupełnij z Palladin.io”, with the existing Palladin icon at the start. Inline
icon rendering remains controlled by the IME; RemoteViews is the fallback.

Successful Android completion restores the exact task of the live non-exported
SourceAutofillAuthenticationActivity with ActivityManager.moveTaskToFront(taskId,
0), then sets the original result and finishes that owner. REORDER_TASKS is used
only for this OS-owned task; no package launcher, Dart task ID or arbitrary
Intent is accepted. Main must not subsequently move its task to the background:
on Samsung that resumed the launcher instead of the requester. Task restoration
failure aborts the original request without reporting success. Source origin,
lease/revocation and one-use consumption checks still precede the callback.
Synthetic OS probes verify exactly one result and requester foreground under
standard and home-behind-picker task ordering; physical OEM acceptance remains
separate. Explicit cancellation retains its existing lifecycle behavior.

Cold source bootstrap may refresh an expired token during its account request.
The loader discards that response and permits one new account request only when
the independent login lifecycle and all authority scope fields remain unchanged.
Logout/login (even the same account), changed authority or a second refresh
rejects preparation before biometric authorization. Publication remains fenced
by the captured authority and source identity. This retries source preparation,
never a cancelled biometric prompt; no additional key or session is persisted.

Queued failures from the same expired access token share its first completed
refresh: later old-token 401s replay once with the current token instead of
rotating it again. Each outgoing request retains the login lifecycle through
token reads, refresh, guarded dispatch and the replayed response; same-account
logout/login cannot adopt an old refresh or successful replay response. A
loopback integration exercises three concurrent 401s through real source
bootstrap and the request-bound biometric MethodChannel, asserting one refresh
and one prompt. Local unlock errors use a neutral unlock-failed message instead
of incorrectly claiming a connection failure.

Password-only regression coverage uses both native input type and HTML password
semantics, including a hidden username from an earlier step and excluded OTP,
confirmation and read-only targets. A synthetic Android requester invokes the
same source result builder as production and verifies the exact original
password field/value, ephemeral Dataset, one result and requester foreground.
These tests pass on the existing matching policy; no Binance-specific heuristic
was added. Debug-only diagnostics expose field-role counts, focused role and
known HTML semantic booleans, never values/text/identifiers. A physical Binance
trace is still required to explain its missing fill despite successful return.

Debug31 physical Binance metadata narrows the unresolved failure: the last of
two FillContexts reports a focused HTML password input; parser roles are zero
usernames and one password. Handoff returns one password in a Dataset. Android
then logs an inactive authentication-result session (NO_SESSION), before it
examines that result. This is a session-lifetime failure, not evidence that
password-only recognition needs a broader heuristic. A real AutofillManager
WebView comparison is required before changing the handoff. A separate first
selection failure reports AutoFillCredentialException; Debug-only boolean
predicates distinguish its binding/staleness/lease boundary without revealing
credential content or weakening those checks.

Debug32 identified the first-selection failure independently: disabled=false,
beforeIssued=true, expired=false. The phone clock was several seconds behind
the server. AutoFill now uses the same existing five-minute issuance admission
allowance as canonical Member reads, via memberLeaseClockTolerance. The original
absolute notAfter remains strict; no expiry grace period or lease extension is
introduced. Canonical maximum-observed-time rollback checks, native source fences
and request expiration remain intact. Deterministic boundary tests cover small
skew, exact allowance, excessive future issuance and expiry during handoff. The
iOS readonly SQLite/crypto runtime also verifies selection while issuance is
still in the permitted future window; this is not a physical-device test.


## Explicit unverified WebView consent (owner decision 2026-11-07)

Android API31+ non-browser current-login requests with exactly one canonical HTTPS
host may enter MANUAL_WEB when verification returns UNVERIFIED. Lookup errors,
missing system services, disabled links, ambiguous/HTTP/malformed origins and
browsers cannot enter it. Save/generation remain unavailable. The generic parser
and exact-host credential filtering are unchanged; no application-specific rule.

The native bridge sends reportedHost separately from an empty verifiedHosts set.
The authenticated existing Entries picker searches only that exact host and shows
the installed app label/package. Selecting a row shows the app, Entry, exact host
and a warning; explicit row selection grants one-operation consent (2026-11-09 decision). Cancel does not decrypt the selected
body. Consent binds request, selected Entry/host and source epoch, is consumed once,
and disappears on invalidation, cancellation or replacement. Final handoff checks
current installed signatures and allowed origin status again, plus existing
source lock/revoke/lease fences. A subsequent successful verification does not
remove the consent requirement of a request initially admitted as MANUAL_WEB.
No association is remembered. iOS extension sessions explicitly reject this
Android-only mode; existing iOS service identifier policy remains unchanged.

This adopts Android's documented authenticated warning/confirmation fallback:
https://developer.android.com/reference/android/service/autofill/AutofillService
Tests cover policy exclusions, exact-host search, EN/PL warning and cancellation,
no completion without consent, revocation during confirmation and one-use binding.
Physical DEGIRO acceptance remains separate from the generic synthetic regressions.


Android package visibility also includes MAIN/LAUNCHER apps. HTTPS-handler queries
alone hide installed launchable apps that declare no HTTP(S) intent filters;
Package Manager then cannot supply their identity/signatures, and domain lookup
fails before manual consent is considered. This visibility declaration enables
inspection only, never verifies a domain, bypasses a signature check, or enumerates
and uploads installed apps. Apps without a launcher or supported HTTPS handler
remain subject to platform visibility limits. No QUERY_ALL_PACKAGES permission.
The provider-UID regression is documented in the Android harness README.


### Entries picker and account labels (Debug38)

The Android picker and global Entries page share `EntriesListView` and
`EntryListCard`. Canonical `MemberIndex.username` is retained in the runtime
projection, candidate and Entry row; the account username precedes the exact
host instead of substituting the Vault name. Matching never infers username
from untyped `searchFields`. Different saved hosts remain excluded from WEB
and MANUAL_WEB, even after clearing the text query.

Legacy compact indexes have no typed username. Only mounted credential rows
may request a local username preview through the existing guarded Entry read;
the temporary body is cleared before returning the username. These previews
are view-local, do not export passwords, do not trigger a full-Vault pass or
make network requests. Lock/source changes discard rows and fence late reads.
The selected body is independently reopened and validated at actual handoff.
Thus the historical “no body read before selection” statement applies to
canonical indexes; it is not claimed for these bounded legacy previews.

Product-owner decision of 2026-11-09: MANUAL_WEB and other consent-required
Android flows use the single pinned warning and an explicit row tap. That tap
both chooses the Entry and requests one-operation consent; there is no second
Fill once action or modal. Consent still binds the exact request, Entry/host and
source epoch and is consumed only at handoff. Double taps cannot start concurrent
fills. Closing before selection grants nothing; cancellation, replacement or
source changes during consent deny the late fill. No association is remembered.
The iOS native picker retains its existing confirmation UI.

The picker is pushed onto the existing shell navigator when it is available,
preserving Palladin navigation; it suppresses the underlying Add FAB. Leaving
the picker cancels the native request. The root fallback is retained for hosts
without an authenticated shell. Navigation changes do not broaden origin policy.

### Warm app requests (2026-11-12, implementation under validation)

After successful source activation, the app retains a value-free preparation
stamp: source ticket, authority revision, Member read/content/publication
revisions, Vault IDs and original lease contexts. It retains no Entry projection
or key. A normal warm request may skip all-Vault synchronization while this stamp
remains valid. Explicit freshness/reconnect repairs and pending mutation or
invalidation reconciliation still take the authoritative preparation path.

Reuse does not authorize filling: every request still passes the durable repair
gate, current metadata revalidation and native source acknowledgement. Lock,
account/source replacement, content changes, active synchronization and expired
leases reject the stamp; final selection/handoff guards remain unchanged.
The independent iOS Credential Provider runtime does not share this app RAM cache.

## Federated sign-in methods

A Credential may remember the external OAuth/social provider (Google, Apple,
Microsoft, GitHub, Facebook) and provider account the user signs in with,
stored as independent `palladin.signin.v2` custom fields inside the encrypted
MemberSecret, with untouched v1 values retained (see
[vault](vault.md#federated-sign-in-methods)). Mobile supports explicit management
in Add, Edit and Entry Details: choose, change, remember and remove a method. It syncs with Web and the browser extension
through the ordinary encrypted Entry.

System AutoFill does not read, suggest or fill this binding. iOS and Android
credential providers run sandboxed and receive only the OS-reported service
identifiers and form fields; they cannot observe OAuth redirects, provider
buttons, sign-in flows or provider sessions in other apps, Safari, Chrome or
other browsers, and Palladin does not try to. No native AutoFill code, cache
record or provider-session data is involved. Credentials with an empty
password (for example OAuth-only accounts) remain excluded from the native
AutoFill cache exactly as before (`AutofillCacheService` skips them and
`AutofillRecord` rejects them), and AutoFill saving still requires a non-empty
password.
