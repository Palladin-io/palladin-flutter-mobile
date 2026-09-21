# Individual Entry sharing — CVT-644 (in progress)

The mobile snapshot crypto boundary, sender list/revoke tab and creation page
are implemented on the feature branch. The isolated guest transport and reception
Cubit now have a mounted receiver page and an app-owned ingress/router host.
Android and iOS have native intake wired to the one-shot Dart RAM handoff.
The explicit account continuation is wired to the existing authentication routes.
First personal-Vault creation is wired inside the received-copy form.
Inbox receipt and eight-event audit presentation are implemented in EN/PL.
Receipt-to-Sharing navigation opens the existing Entry tab using the encrypted
Member loader and session-fenced local metadata. Native device/domain acceptance
and real backend account/save E2E remain pending. Foreground Inbox repair is wired
through the app lifecycle with session-fenced async results. Local tests
are not evidence of deployed end-to-end sharing.

## Inbox and audit presentation checkpoint (2026-09-21)

Receipt navigation now has 30 focused cases: exact EN/PL Inbox-to-Sharing
navigation without initializing the secret editor, unavailable target/access,
and late results after account/org/membership, key, Inbox, Vault, lifecycle or
route changes. It uses the existing Member loader even for an unopened Vault;
no server label or supplied URL becomes a destination. See
[notifications](notifications.md). This supersedes the historical pending
navigation statements below, not the backend/device acceptance gates.
Full regression: **1,821 Flutter PASS / two existing plugin-only skips**, including
six structural budgets; analyze, notices and staged-tree Gitleaks 8.30.1 PASS.
Initial mounted harness failures (missing shell scope and an invalid synthetic
lifecycle transition) were corrected in the harness, not hidden by production
fallbacks. No CI, native app build, merge or deployment was run.

Follow-up: foreground repair is now app-owned, with immediate ready-context and
30-second refresh, one in-flight repair per generation, independent account/org
authority and redaction on background/lock. Feed/summary/pagination/local-label
results and failed read rollbacks cannot revive an old session. **33 new cases;
1,791 Flutter PASS / two existing plugin-only skips**, including six budgets;
analyze/notices and full staged-tree Gitleaks 8.30.1 PASS. Tests use substituted
repositories/index and a controlled clock, not real backend/device delivery.
No CI, native build, merge or deployment. Receipt-to-Sharing navigation remains
open alongside the wider epic acceptance gates.

Localized receipt details, eight sharing audit types, external-recipient
attribution, filters and legend are implemented. The receipt and confirmation
sentence wrap fully at 320px/150%; identifiers use prefix/suffix and Entry labels
use the existing unlocked local resolver. Eighteen new cases cover taxonomy,
labels/redaction and mounted EN/PL cards/legend. Full Flutter regression:
**1,758 PASS / two existing plugin-only skips**, including six structural budgets;
analyze and notice verification PASS. Synthetic Inter renders were inspected in
light/dark. These are presentation tests, not live Inbox or backend/device
acceptance; navigation remains open. Foreground repair was added in the next
increment described in [notifications](notifications.md). Full staged-tree
Gitleaks 8.30.1 passed with the repository configuration and no allowlist changes.

## Received-copy projection

`EntryShareCopyProjectionService` maps an independently decrypted snapshot to a
new canonical `MemberSecret`. It preserves selected strings without trimming,
Unicode normalization or guessed required values. Missing required fields are
enumerated for explicit recipient completion; completion cannot override received
fields or inject policies. An oversized title needs an explicit replacement,
never truncation. The generated Member index must pass its own reader before a
copy can be prepared, so unsupported input cannot create an unreadable index.

All field policies are `never`, Discovery is disabled, custom field identities
are fresh, and source icons, grants, memberships, history and Script references
are absent. A Script needs a recipient-provided execution description; its new
execution metadata has no parameters/references and does not return results to
Agents. This does **not** exclude existing members or fully trusted FULL Agents
of the destination Vault; the destination picker explicitly explains that access.

`EntryShareTotpCodec` converts native and custom TOTP into canonical configuration
maps without permissive algorithm fallback or label normalization. Duplicate or
unsupported parameters, conflicting issuer labels and unsupported values reject
the copy with a value-free typed error, never silently drop the field. URI labels
are decoded once. The sender now explicitly includes even an empty issuer so an
issuer-less account containing a colon survives its mobile roundtrip.

Thirty-two local cases cover all four Entry types, incomplete snapshots, private
policies, independent custom identities, exact TOTP configuration/labels and
native libsodium encryption/decryption with different fresh Entry DEKs. These
prove projection and crypto composition only. The save boundary and mounted
receiver now use this service as described below; account continuation and
cross-client HTTP acceptance remain required. These tests do not establish
limit=1 end-to-end acceptance.
Projection checkpoint (2026-09-21): full Flutter suite **1,588 PASS / two existing
plugin-only skips**, analyze, notices and six structural budgets PASS. No CI,
native app build or deployment was run.

## Received-copy save boundary

`EntryShareCopyService` composes the private projector with existing Vault/Entry
crypto and canonical creation routes. Destination wrappers bind to the selected
Vault, captured organization/principal and independently returned current key
epoch/member generation; metadata revision binds to the top-level Vault revision.
It obtains a server creation challenge and seals revision one with a fresh Entry
DEK. No source key, Agent policy or sharing-delivery request is reused.

`EntryShareCopyDatasource` owns an isolated transport, not the authenticated Dio
singleton. A request captures one token only after checking the original RAM key
generation and compares its principal/organization/authorization claims with the
flow owner. It neither refreshes tokens nor retries or follows redirects. Shared
`EntryShareHttpClient` provides bounded streams, configured certificate pinning
and value-free errors to both guest and copy datasources; guest operations still
never supply account authentication. Vault/challenge/create response budgets are
256 KiB/4 KiB/16 KiB, respectively.

Preparation wipes copied private/Vault/discovery keys on failure, cancellation
and completion, including late crypto results. A prepared copy retains only its
exact encrypted request and structural destination/owner in RAM. Explicit retry
reuses that request and challenge ID. AutoFill is invalidated before a write; an
uncertain outcome leaves it invalidated. A failed cache rebuild cannot turn a
confirmed create into another Entry. Canonical Entry sealing now also wipes its
new DEK and any allocated plaintext buffers when descriptor/projection building
throws before encryption starts.

`EntryShareCopyCubit` requires the original reception lifetime and captured
authenticated owner. Construction sends nothing. Save/retry block duplicate taps
synchronously; all awaited work is fenced by owner, epoch and original deadline.
After preparation it drops the snapshot and retains only the encrypted retry.
Clear closes its owned service, cancels requests, wipes private-key copies and
disposes the prepared request. An invalidated flow cannot rebind to another
account or renew its deadline. The receiver now wires clear to lock, background,
route departure and auth/key changes, and its injected factory creates a fresh
service per flow rather than closing a shared singleton.

Tests use real loopback HTTP and native libsodium for decryptable canonical
creates, byte-identical retry after socket loss, scope/version substitutions,
session replacement, cancellation and Cubit lifecycle. The loopback server is a
synthetic contract fixture, not the Palladin backend. Account continuation and
actual HTTP/device end-to-end acceptance remain required.

Save-boundary checkpoint (2026-09-21): **44 new cases; full Flutter 1,632 PASS /
two existing plugin-only skips**, analyze, notices and six structural budgets
PASS. No CI, native app build or deployment was run.

### Mounted save form and destination authority

An already authenticated, verified, onboarded, unlocked recipient with
`vaultManage` can explicitly save the received snapshot. `EntryShareCopyPanel`
replaces the receiver body without a new route or delivery. It requires manual
destination selection, preserves exact title/completion strings, and uses shared
inputs, warnings, dropdown and pinned action footer in EN/PL. Missing required
fields and invalid titles remain editable. The access warning explains existing
destination members and fully trusted Agents; source policies remain excluded.

Destination discovery uses the copy flow's isolated, account-bound transport,
not global Vault-list state. Pages contain up to 50 summaries and 2 MiB; total
work is capped at 2,000 rows, including duplicates across changing pages. Each
summary's top-level Vault ID and key epoch plus the captured organization and
principal independently bind encrypted descriptors. The list contract does not
carry an organization or metadata revision; neither is invented from a wrapper.
The selected detail is fetched afresh before Save and additionally binds its
top-level metadata revision. Corrupt rows are omitted with an explicit notice,
without hiding usable Vaults. No N+1 detail reads, challenge or Entry creation
occurs while listing. Names are flow-local RAM; copied private/Vault/discovery
keys are wiped after use, on cancellation and after late crypto completion.

The form owns its copy Cubit but shares the original reception lifetime. Lock,
background, account/key replacement, expiry and route departure cancel requests
and clear completion controllers and destination names. After preparation,
editable controls disappear and retry can only send the original encrypted
request. Confirmed save disables another copy action in this reception; cancelling
before the write returns to the same received snapshot. Closing cannot undo an
already accepted server write, which is disclosed separately from local cleanup.

Local widget tests exercise the real crypto/save service with substituted
datasources: one receive and ACK, explicit destination/completion, decryptable
private create, byte-identical retry, no duplicate copy, corrupt-row isolation,
empty/error states, permission gates and cancellation through list/create. They
also cover original expiry and the PL dark 320px/150% layout with keyboard inset.
Synthetic Inter captures are visual evidence only, not device or backend E2E.
Guest registration/login/unlock, email verification and the combined account/save
acceptance remain required. The first personal-Vault action is described below.

Mounted-save checkpoint (2026-09-21): **25 new cases; full Flutter 1,657 PASS /
two existing plugin-only skips**, analyze, notices, six structural budgets and
staged-tree Gitleaks PASS. No CI, native app build, merge or deployment was run.

### First personal Vault inside the received-copy form

After a successful, fully empty destination list, a recipient with `vaultCreate`
can explicitly create the personal Vault without leaving the form. A failed list
or a list with unreadable Vaults never implies an empty account. Creation keeps
the same snapshot, receipt, ACK and original RAM deadline. The recipient must
still choose the refreshed destination and explicitly save the Entry; neither
action happens automatically. EN/PL reuse the existing form, tokens and footer.

The copy datasource uses its isolated captured-account transport for `GET
/api/account`, `POST /api/vaults/creation-challenges` and `POST
/api/account/default-vault`. The account's top-level user id must match the
independently captured principal before existing `VaultCryptoService` seals the
new Vault. Member key version comes from that authenticated account contract;
organization/principal are never inferred from the generated wrapper. Only
ciphertext and structural fields leave the client. The existing onboarding
provisioner's global transport/persistent marker are not used by this flow.

Duplicate taps are blocked before the first await. Ambiguous failure retains
one exact encrypted request/challenge in RAM; explicit retry cannot create a
different package. Definite 4xx errors except 408/429 retire that request. Only
a conflict from the default-Vault POST requests list reconciliation; a challenge
conflict stays a failure. A conflict does not assert that a Vault was created.
Confirmed creation is not repeated when the subsequent list fails or remains
empty. Refresh is read-only, and destination selection remains explicit.

Every await is fenced by account, key generation, cancellation and original
deadline. Private-key copies and returned VK/VDK are wiped on completion or
invalidation, including late crypto results. Background/lock remove form values
and cancel the request; a late response cannot revive it. Local cancellation
cannot undo a server write that was already accepted.

Sixteen added service cases use real loopback HTTP and native crypto; seven
added mounted cases use the real crypto/save service with substituted transport.
They include empty/permission/corrupt-list gates, exact retry, scoped conflicts,
late crypto/key cleanup, expiry, list repair, background/lock and explicit
creation → destination selection → decryptable private Entry with one receive
and one ACK. Synthetic EN light 390px and PL dark 320px/150% captures were reviewed.
These tests do not prove real signup/email/OAuth, a combined production-router
guest-to-save path, native devices or a deployed user test environment.

First-Vault checkpoint (2026-09-21): **1,728 Flutter PASS / two existing plugin-only
skips**, including six structural budgets; analyze and notice verification PASS.
The 41 receiver widget cases also pass with the synthetic Inter font. No CI,
native app build, merge or deployment ran.

### Combined guest login and first-Vault copy acceptance

`test/core/router/entry_share_guest_save_test.dart` composes production ingress,
navigation/router, receiver host/page, account continuation, LoginPage/AuthBloc
and the copy form/services with real isolated loopback HTTP and native libsodium.
The native channel, LoginCubit, account repository and token storage are
substituted; the loopback server is a synthetic contract fixture, not Palladin.
The test enters the login form rather than manually claiming a transfer.

Three cases cover success, an invalid-login retry and an ambiguous copy-write
retry. The fixture refuses a second delivery. Each case asserts one session,
one delivery and one display confirmation, the same reception lifetime after
login, explicit first-Vault creation, manual destination selection and completion
of a missing username before Save. Retry sends byte-identical ciphertext with
one Entry creation challenge. The resulting private Entry is independently
decrypted with the recipient's newly created Vault key. Observed routes contain
only `/login` and `/share`; guest requests have no account authorization/cookies,
and request bodies exclude the tested plaintext fields and encoded private key.

This adds combined client-composition evidence beyond the earlier separate
router and form tests. It does not exercise real login/KDF, signup, verification,
OAuth, native callbacks, backend receipt accounting or deployed end-to-end
acceptance. Those release gates remain open. The loopback test yields to real
I/O before advancing the widget fake clock; the initial harness timeout required
no change to production Vault creation.

Combined-client checkpoint (2026-09-21): **1,740 Flutter PASS / two existing
plugin-only skips**, including all six structural budgets; analyze, third-party
notice verification and staged-tree Gitleaks 8.30.1 PASS. No CI, native app build,
merge or deployment ran.

### Combined guest registration, verification and copy acceptance

The same production-router test now also mounts the real `RegisterPage`,
`RegisterCubit`, password KDF/crypto, recovery backup/confirmation,
`VerifyEmailPage`/Cubit and `DefaultVaultProvisioner`. Three added cases cover
successful verification, a still-pending email claim and a failed refresh followed
by explicit retry. Signup and Vault/Entry requests use real loopback HTTP;
the server, session-claim refresh, token storage, HIBP and native channel remain
synthetic. No real email or backend authentication is claimed.

After the email-app background/foreground sequence, verification creates the
first encrypted Vault and returns to the same reception lifetime. All cases
retain exactly one open, delivery and confirmation; the fixture rejects a second
delivery. Destination selection, missing username completion and Save remain
explicit. The new private Entry is independently decrypted. Neither recovery
words, the master password nor the private key occur in captured request bodies.
Pending/failed verification cannot provision the Vault or bypass the gate.

Two additional EN 390px/light and PL 320px/dark/150% cases edit registration above
the keyboard and discard reception without remounting or erasing the account
form. They reproduced a horizontal sign-in prompt overflow and an oversized
pinned header that obscured the email input. Registration now wraps the prompt
and scrolls its header with the form; a separate reduced-height scaffold
regression reproduced the original vertical overflow. Other pinned-action
variants retain their behavior.

This extends client-composition evidence, not live signup/mail/device acceptance.
Combined unlock is covered by the subsequent checkpoint below. OAuth onboarding,
actual backend receipt accounting and the deployed test environment remain open
release gates.

Registration checkpoint (2026-09-21): **six new cases; 1,827 Flutter PASS / two
existing plugin-only skips**, including six structural budgets; analyze,
third-party notices and full staged-tree Gitleaks 8.30.1 PASS. All eight combined
cases also pass with a supplied Inter font. EN/PL initial and keyboard captures
were inspected for form geometry; the unthemed RichText wordmark still uses the
widget harness's default block font, so these are not full visual approval or
native-device evidence. No CI, native app build, merge or deployment ran.

### Combined locked-account unlock and copy acceptance

The production-router fixture also starts with a restored, verified, locked
account. It receives and confirms the snapshot before the explicit account
action opens the real `UnlockPage`/`UnlockCubit`. Native Identity KDF and key
decryption use a generated synthetic account envelope served by loopback HTTP;
the production provisioner creates its first Vault before the original reception
resumes. The final Entry is independently decrypted after manual destination
selection, missing-field completion and Save.

Three added cases cover success, wrong-password retry and a failed required
default-Vault POST followed by retry. Failures retain the locked state and pending
reception; no member key is available and no Entry write occurs. Every successful
case preserves the original lifetime object and exactly one open/delivery/ACK.
Sharing requests remain anonymous, routes contain only `/unlock` and `/share`,
and captured request bodies exclude the tested plaintext/password/MK/private key.
Account/session restoration, token storage, native ingress and the server remain
synthetic. The biometric store reports unavailable; no enrollment or read occurs.
The existing mobile MK-persistence release blocker is unchanged.

Two additional EN 390px/light and PL 320px/dark/150% cases keep the unlock password
editable above the keyboard and preserve the mounted form after discarding
reception. Pixel assertions on these and registration cases reproduce a light
background bloom painting over the otherwise opaque sharing notice. The account
body now has a stable `ClipRect`, protecting its sibling notice without remounting
the account form or changing shared gradient geometry. This is a scoped rendering
fix, not a redesign of authentication.

Combined OAuth onboarding is covered below. Real backend authentication/receipt
accounting, mail/native device acceptance and the deployed user environment
remain required.

Unlock checkpoint (2026-09-21): **five new cases; 1,832 Flutter PASS / two existing
plugin-only skips**, including six structural budgets, after the paint fix.
Analyze, notices and full staged-tree Gitleaks 8.30.1 PASS without exception
changes. All 13 combined account cases also pass with supplied Inter; EN/PL
initial/keyboard renders confirm layout and the corrected notice paint. The
RichText wordmark retains the widget harness's block font, so this is not full
visual or native-device approval. No CI, native app build, merge or deployment.

### Combined Google onboarding and copy acceptance

The production-router fixture drives the Google action through the real AuthBloc
and onboarding wizard, native KDF/libsodium, recovery backup/confirmation, account
setup over loopback HTTP and the default-Vault provisioner. Success, provider
cancellation/retry and account-setup failure/retry preserve the same reception
lifetime and one open/delivery/ACK. The failed setup leaves the account unonboarded
without a member key, Vault or Entry write. Explicit destination selection,
missing-field completion and Save produce an independently decryptable copy.
Background/resume during the provider wait does not redeem the link again.

The Google repository result, token storage, HIBP, native channel and server are
substituted; this is client-composition evidence, not real Google/backend/device
E2E. Biometric storage is unavailable and never enrolled/read. Captured request
bodies exclude the tested plaintext, password, mnemonic, MK and private key.

EN/light/390px and PL/dark/320px/150% keyboard/cancellation cases keep the account
form editable and mounted. They reproduced a pinned header overflowing the
short viewport; both centered-footer variants now scroll the header, while the
master-password Continue action remains pinned (also checked independently).
The setup-retry case reproduced duplicate SnackBar Hero tags during overlapping
wizard/route transitions; clearing the old error SnackBar when the error state
clears removes the conflict without delaying account continuation.

OAuth checkpoint (2026-09-21): **six new cases; 1,838 Flutter PASS / two existing
plugin-only skips**. Six structural budgets, analyze, notices and full staged-tree
Gitleaks 8.30.1 PASS without new exceptions. All 18 combined account cases also
pass with supplied Inter. EN/PL initial/keyboard renders confirm scrolling,
pinned action and notice geometry; the wordmark retains the harness block font,
so this is not full visual/native-device approval. Same mobile/root Draft PRs;
no CI, native app build, merge, deployment or gitlink change.

### One-shot account transfer and explicit account continuation

`EntryShareReceptionCubit.detachForAccount()` validates the original owner before
moving an idle reception into `EntryShareReceptionTransfer`. It cannot run during
a request or a suspended email detour. The old Cubit immediately loses its
snapshot, capability and transport; closing the old widget cannot close the
transferred transport. The transfer keeps the same session, verification gates,
OTP generation (including an uncertain send retry), snapshot and display ACK.
There is no new open/delivery/confirmation request or reconstructed link.

The transfer is an opaque, one-shot RAM owner with the original shortened
wall/monotonic lifetime and its own expiry timer. Resume requires a non-anonymous
owner and a separate authoritative read that matches it. A transfer that started
on an account cannot move to another principal or organization; the same-account
unlock can adopt the newly established key generation. Concurrent/second resumes,
late owner results after disposal/expiry and authority failures cannot resurrect
it. Expiry/abandonment closes transport, wipes key/bearer bytes and drops the
snapshot/session references. Successful resume moves ownership into a new Cubit
and retires the transfer without destroying the moved material.

The app-owned `EntryShareAccountContinuation` now calls this primitive only after
the recipient explicitly chooses login, registration or completing/unlocking an
existing account. The host transfers ownership before leaving, and the router
returns to constant `/share` only after onboarded, verified, unlocked identity
and independent organization/authorization/key-generation authority agree. No
link, snapshot, key or share ID enters router state. A guest's cancelled/failed
login remains retryable; the first authenticated principal and organization bind
the flow. Logout, relock, replacement keys/permissions/account/organization, a new
link, unrelated routes, cancellation, expiry or detach discard it. Generation
comparisons use the auth state that verified the previous owner, not a newer
observation while an unlock read is pending.

Only this explicitly detached account flow may retain its received snapshot in
RAM while an allowed login/register/verification/onboarding/unlock route is
backgrounded for email/OAuth. It performs no reception operations in the
background, revalidates on return and never renews the original deadline. Normal
receiver backgrounding still discards delivered plaintext. Process death loses
the copy; there is no persistence or deferred replay. PrivacyRuntime defers its
optional sheet while `/share` is visible so it cannot accidentally retire the
returned copy; consent state is unchanged.

Coordinator tests exercise real snapshot decryption and reuse the same receipt,
ACK and lifetime across account binding. Mounted host tests click the actual
login/register CTAs and return to the same remote session after replacement of
the receiver route. Auth and transport are substituted. The first-Vault form now
has separate evidence above; combined guest-to-copy-save and real
email/OAuth/limit=1 HTTP/device E2E remain
required. These narrower tests do not establish those outcomes.

`EntryShareAccountFrame` now exposes local cancellation on login, registration,
verification, onboarding and unlock. Its inline confirmation uses the current
transfer generation, so an obsolete action cannot discard a replacement flow.
It clears the RAM reception only: no link revocation, logout or account-setup
cancellation. The account form keeps its element and entered text. Expiry removes
the notice without renewing the deadline. The opaque themed notice scrolls within
half the keyboard-adjusted viewport; it never consumes the entire form area.

Six new widget cases exercise the production login page, real AuthBloc and
production router, including delayed independent authority, exact `/share`
return, manual one-shot transfer claim, cancellation, expiry and EN/PL keyboard
layouts. LoginCubit and account repository are substituted; the returned route
uses a placeholder rather than the mounted receiver/save host. Two coordinator
cases cover cancellation during authority lookup and stale cancellation after
replacement. A PL 320px/150% test reproduced a login sign-up-row overflow; the row
now wraps and the email field remains editable above the keyboard. This is not
registration/verification/unlock form acceptance or combined guest-to-save E2E.

Cancellation checkpoint (2026-09-21): **eight new cases; 1,705 Flutter PASS / two
existing plugin-only skips**, including six structural budgets. Analyze, notices
and staged-tree Gitleaks PASS. Synthetic EN light 390px and PL dark 320px/150%
captures informed the opaque bounded notice; widget checks additionally edit the
login email above the keyboard. No CI, native app build, merge or deployment ran.

Account-wiring checkpoint (2026-09-21): **23 added cases; 1,697 Flutter PASS / two
existing plugin-only skips**, including six structural budgets. Analyze, notices
and staged-tree Gitleaks PASS. EN light 390px and PL dark 320px/150% synthetic Inter
captures keep the optional account actions and guest reception accessible.
The two reproduced
failures were a late optional privacy sheet and a repeated auth observation while
unlock authority was pending. No CI, native app build, merge or deployment ran.

Transfer checkpoint (2026-09-21): **17 added cases; 1,674 Flutter PASS / two
existing plugin-only skips**, analyze, notices, six structural budgets and
staged-tree Gitleaks PASS. Existing receiver/host cancellation tests also pass.
No CI, native app build, merge or deployment was run.

## Guest reception boundary

`EntryShareRecipientDatasource` owns a separate Dio/IO transport, never the
authenticated singleton. It has no auth/refresh, cookies, analytics or HTTP
logging interceptors and never follows redirects or automatically retries.
System certificate trust and configured environment SPKI pins still apply.
Only explicit POST methods exist: session open, OTP request/verification,
optional secret verification, delivery, display confirmation and ending the link.
Capability/proof strings are request bodies, never URLs or headers. The decryption
key is not a transport input. Errors expose only a typed, value-free exception.
Responses are bounded streams (16 KiB metadata; 512 KiB delivery, allowing a
base64-encoded 256 KiB ciphertext and scope), decoded locally with strict UTF-8.
Those are device resource budgets, not duplicated server business rules.
Cancellation covers both awaiting headers and consuming a streamed response;
buffer cleanup and stream cancellation run on every exit.

`EntryShareReceptionCubit` owns one transport, link capability and recipient
session. The hosting page must supply an independently captured owner record and
reader (guest is an explicit nullable-principal record, not absent authority).
Every success/error and post-await publication rechecks that owner, generation
and expiry. Clear/dispose cancels and closes the transport, wipes key/bearer arrays
and drops the recipient token and plaintext references. The receiver page wires
lock, account/permission/key changes, route departure and immediate revalidation.
Its ordinary background-retention exception is the pre-delivery email detour
below, without decrypted Entry content. The separate explicit account transfer
owns the bounded account-detour exception described above.

No network call occurs on construction. Open and each subsequent operation are
explicit. Named recipient OTP and optional password/PIN must both succeed before
the client offers delivery/end; the server remains the authorization boundary.
Unknown future gate values stay readable without enabling an unsupported action.
OTP send retry retains its pending generation and blocks verification with an
older code until the send resolves. Delivery retry reuses the same session and
never opens another one. Confirmation is a separate action after display, never
automatic on decryption; failed confirmation retains the copy and retries only
confirmation. Ending drops the copy locally only after an authorized success.

Crypto consumes the canonical delivery scope and independently requested share ID
through `EntryShareCryptoService`; failed authentication retires the capability,
not a fallback plaintext path. `EntryShareLifetime` carries the original 15-minute
RAM ceiling from ingress through reception and can only shorten to session expiry.
The ingress host must pass that same instance to the Cubit; constructing a new
deadline on mounting or resuming is not a continuation. Both wall and monotonic clocks
are checked before actions and after awaits, so clock rollback or delayed timers
cannot extend it. Invalid/unusable expiry fails closed for this local secret
lifetime boundary. Immutable Dart strings can be dropped, not securely zeroed.

Tests cover 19 actual loopback-HTTP cases and 31 reception/native-crypto cases:
all request contracts, redirects/cookies, malformed/oversize bodies, cancellation
before/after headers, optional gates, exact retry, separate ACK, concurrency,
scope substitution, delayed crypto and both success/error after owner changes.
The loopback server is a synthetic fixture, not the Palladin API or real email
provider. Auth/save continuation and device E2E remain required.

### Recipient link policy and OTP countdown

The session transport reads link `shareExpiresAt` and `maximumReceipts`
separately from the short session's `expiresAt`. Missing optional presentation
metadata is omitted, never replaced with session validity. The receiver shows
localized link validity and the configured receipt limit, with an explicit
shared-limit notice for anyone-with-link. It does not claim remaining receipts.
Entry type is shown only from the authenticated decrypted snapshot.

The initial session's `otpRetryAfterSeconds` and successful OTP POST's HTTP 200
`retryAfterSeconds` supply the visible resend countdown. The server remains the
cooldown authority. The Cubit anchors presentation to the original decreasing
RAM lifetime; foreground ticks, email detours and one-shot account transfers do
not start a new minute. It blocks a new generation while waiting but preserves
an uncertain same-generation retry. Verification and cleanup cancel the ticker.
No additional clock, storage, polling or automatic OTP request was introduced.

Nine new transport/Cubit/widget cases cover optional policy fields, independent
expiry, initial shared cooldown, ticks, email/account continuation, residual
acknowledgement retry and EN/PL rendering. Full Flutter regression: **1,737 PASS /
two existing plugin-only skips**, including six structural budgets; analyze and
notice verification PASS. All 44 receiver widget cases also pass with synthetic
Inter. EN light 390px and PL dark 320px/150% captures were reviewed. These are
local fixtures, not device, real email or deployed HTTP acceptance.

### Receiver page and email detour

`EntryShareReceiverPage` uses one caller-supplied Cubit and requires a stable
`AuthBloc` context. It opens no network session until the explicit Open action.
The production host owns disposal (`ownsCubit: false`); standalone callers retain
the default page-owned disposal behavior.
Separate EN/PL email-code and optional PIN/password inputs clear their exact
values before sending; format errors remain inline. Unsupported future gates
remain readable but cannot enable delivery. The receive action is pinned, and
the field preview reuses `EntryShareFieldCard` with the sender form. Concealed
and TOTP fields start masked; reveal/copy revalidate ownership immediately.
Only explicit Copy uses the existing 45-second conditional clipboard clear.
Immutable strings and external clipboard histories cannot be securely erased.

The first display acknowledgement is scheduled after a rendered frame and after
delivery finishes, not when decryption returns. A failed ACK retains the copy;
retry sends only the ACK. Ending a link needs a separate confirmation sheet,
which closes on authority loss. A five-second foreground ownership repair backs
up the immediate checks. Pop, covering the route, account/lock/permission/key
changes and disposal retire the capability and drop controllers/plaintext.
Background also destroys an already received copy or an in-flight operation.

An **idle named-recipient session with an acknowledged OTP request, still awaiting
OTP verification and with no delivered snapshot**, may suspend in RAM while the
user checks email in another app. Controllers and the visible body are cleared,
all remote operations are blocked, and the original wall/monotonic deadline and
expiry timer remain unchanged. Foreground return revalidates the original owner;
a subsequent background transition fences a pending resume. There is no durable
storage, new session, redelivery, or automatic proof submission. Detach, expiry,
auth change, route exit, any in-flight request, or an already verified email
falls back to full discard. This bounded pre-delivery exception fixes a reproduced
widget failure where reading the email made the code impossible to submit.

Sixteen mounted receiver tests cover explicit gates, ACK timing/retry, clipboard,
end/cancel and sheet invalidation, delayed failures, plaintext/input cleanup,
email app roundtrip, unknown gates, route changes and ownership repair. Six shared
field-card tests cover mask/reveal and late, denied or failed authorization. The
31 Cubit cases include seven email-suspension lifecycle/deadline/operation tests.
Synthetic Inter renders were reviewed in light EN 390px and dark PL 320px/150%,
including the destructive sheet and keyboard. They are not physical-device or
real API/email evidence. The ingress host passes only a RAM-owned capability and
waits for stable auth/foreground; device acceptance is a separate release gate.

### App-owned receiver host

`PalladinApp` owns `EntryShareIngress` and `EntryShareNavigation`. Navigation waits
for the foreground and passes only the constant `/share` to GoRouter, never the
incoming URL, share ID, fragment or route extras. The public route remains usable
for guests, new/unverified accounts and locked users; it does not grant Vault
access. Close returns to `/`, where normal account/Vault guards apply. Framework
deep-link routing is disabled on Android and iOS and the router overrides the
platform default location. iOS intercepts before `app_links` as described below.

`EntryShareReceiverHost` waits for stable AuthBloc identity and an independent
`EntryShareRecipientAuthority` read before consuming the pending capability.
An explicit guest never reads account-token storage. Authenticated ownership
binds the expected principal to local token claims, authorization version and
RAM key generation, without requiring an unlocked Vault or offline policy.
This is local lifetime ownership, not server authorization. Token decode failures
log only the exception type, never token/parser excerpts.

The host passes the original lifetime to a fresh owned transport/Cubit. Its async
owner lookup is fenced by ingress generation, auth/key identity and host epoch.
New same-ID links dispose the old Cubit and its confirmation sheet; stale lookup
successes/errors cannot affect the replacement. Background lookup waits in RAM
under the original deadline; a mounted receiver retains only its narrowly scoped
email detour. Route cover, auth failure/change, detach, close and disposal clear
the capability. Close is local disposal, never server-side link termination.

Tests cover 19 mounted host cases, five local-authority cases and 11 navigation/
production-router cases. They include auth restoration, guest/new/locked account
routing, replacement races, email-app return, close during lookup, original
deadline continuity and no automatic remote open. Router observations contain
only `/share`; a defensive redirect also strips query/fragment from that route.
These tests substitute the channel/auth/transport and do not prove physical
Android/iOS callbacks or real API/email/account continuation.

Host checkpoint (2026-09-21): full Flutter regression **1,556 PASS / two existing
plugin-only skips**, analyze, notices and six structural budgets PASS. The added
JWT logging test checks that malformed payload contents never appear in logs.
No CI, APK/IPA or deployment was run.

## Native intake and RAM handoff (device acceptance pending)

`EntryShareLinkService.parse` compares the original bounded URL against the exact
configured origin and canonical share UUID/fragment. It rejects URI-normalized
aliases, queries, credentials, alternate hosts/ports, escaped paths and extra
fragment fields before transferring owned key/bearer bytes. Errors remain typed
and value-free; the full URL never becomes a route or display value.

`EntryShareIngress` owns one unclaimed capability and listens on
`io.palladin.mobile/entry-sharing`. Native `pending` messages contain only a
monotonic generation. `takePending` transfers the URL once together with
`generation`, `receivedAtUnixMs` and `ageMilliseconds`; no parameters are sent.
An empty/invalidated native slot returns its generation without a URL. Newer
announcements invalidate the previous Dart generation immediately, even before
the new payload arrives. Delayed older replies, duplicate events, disposal and
explicit clear cannot revive it. Native residence, conservative channel wait and
subsequent Dart residence all count against the same wall/monotonic deadline.
Expiry wipes unclaimed buffers. Taking is version-fenced and one-shot; the host
then owns disposal and must clear an active Cubit on every version change.

Android uses a separate `EntryShareLinkActivity` with no saved state/history,
excluded from Recents and its own single-instance task. It clears its local
Intent before `super.onCreate`, accepts only the configured canonical HTTPS
sharing URL, publishes to the process-memory `EntryShareMailbox`, starts
MainActivity without URL/extras and removes its temporary task. History restore
does not replay the link. MainActivity rejects direct HTTP(S), sharing and
fragment-bearing Intents before Flutter/plugin callbacks. The default Flutter
deep-link handler is disabled. A channel attachment fence prevents an older
Activity's disposal from detaching a newer engine; the pending mailbox's finite
timer survives reattachment and `takePending` removes its copy.

The Android Gradle property `PALLADIN_SHARING_HOST` defaults to `sharing.invalid`.
An approved build must provide the exact host matching the independently checked
Dart `PALLADIN_SHARING_WEB_ORIGIN`, plus the matching public domain association.
The manifest is narrowly scoped to HTTPS `/share/`; it deliberately does not
upgrade HTTP secret links. No Palladin cloud host is a runnable default here.

This bypass is required because installed `app_links` 6.4.1 retains initial/latest
URLs and its Android handler logs `Intent.toString()`. It remains in use for
existing non-sharing email verification; the generic Dart unknown-host log is
now value-free, but this work does not claim a complete audit of that legacy
email/native path. **Real domain association and device/mail/browser acceptance
are still missing.**
Do not enable sharing release on the basis of these unit tests. No attempt is
made to erase browser/OS-originated copies outside Palladin's control, and native
or Dart immutable URL strings can only be dropped, not securely zeroed.

Verification: 14 channel/handoff tests, eight deadline tests, three added parser
tests, two reception deadline-continuity tests and eight JVM mailbox tests.
Full Flutter suite: 1,520 PASS / two existing plugin-only skips; analyze, notices
and six structural budgets PASS. A standalone compiler check covers the two new
Kotlin intake files against Android/Flutter APIs, using stand-ins only for the
generated R and MainActivity symbol. It is not a complete native app compilation
or device test. No APK/IPA, CI or deployment was run.

### iOS Universal Link boundary

`SceneDelegate` consumes a single browsing activity before `super` can retain its
connection options or forward to plugins. `EntryShareNativeIngress` captures only
a canonical HTTPS URL for the independently configured host; other candidates
publish an invalidation. Before forwarding cold-start options, the original
`NSUserActivity` has its URL, referrer, userInfo, title, keywords, restoration
identifiers and Spotlight attributes cleared, and Handoff/search/prediction are
disabled. Warm continuation is consumed without forwarding the activity. No raw
link enters `app_links`, routes, restoration data, logs or persistent storage
through these sharing handlers. Immutable URL strings can only be dropped.

Direct HTTP(S), fragment-bearing and sharing custom URLs are rejected, not
treated as verified Universal Links. Warm URL-context sets forward only unrelated
URLs. Cold sets containing an unsafe immutable URL context are rejected as a
whole and are **not** passed to Flutter's retaining connect callback; the
storyboard engine is registered for later lifecycle callbacks. This rejection
branch needs device startup/regression acceptance. Multiple sharing activities
fail closed instead of choosing arbitrary Set order. Sharing restoration is
rejected, and a scene that received sharing does not produce a restoration
activity. AppDelegate launch dictionaries and legacy URL/continuation callbacks
apply the same interception boundary. Existing non-sharing callbacks continue
to `super`; real email verification and OAuth regression remain required.

The UIKit/Flutter-free `EntryShareMailbox` shares Android's channel contract and
one-shot generation semantics. It uses wall time plus `CLOCK_MONOTONIC_RAW`,
which includes system sleep, for the original 15-minute ceiling. A main-queue
expiry drops unclaimed state; take/reattachment never restarts its deadline.
Plugin attachment IDs prevent an obsolete engine from taking the newer slot or
detaching its channel. Scene disconnect and timer expiry invalidate only their
expected generation, never a newer link received by another scene.

`PALLADIN_SHARING_HOST` is an iOS user-defined build setting, defaulting to
`sharing.invalid` in every flavor, used by Info.plist and the `applinks:`
entitlement. Approved release configuration must override it with the exact host
matching Dart `PALLADIN_SHARING_WEB_ORIGIN`. Associated Domains capability,
provisioning and the hosted AASA file must match the actual bundle identity,
including production-identity store tests against staging. These are not
configured or verified by a passing parser test.

Run the standalone native core tests on macOS with
`swift test --package-path ios/EntrySharingCore`. Runner compiles the same source
files directly; the package is a local test harness, not a new runtime dependency.
Twelve tests cover one-shot transfer, replacement/rejection, expiry including
rollback, canonical URL boundaries, activity cleanup, unrelated activity/URL
classification and late scene cleanup after replacement.
Narrow `swiftc -typecheck` also passes for the real AppDelegate, SceneDelegate and
bridge against UIKit/Flutter simulator headers, using the existing local AutoFill
framework module and the generated registrant header. This does not link/build
the app, validate provisioning or execute UIKit callbacks. No IPA/CI/deployment.

References: [Flutter scene lifecycle](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate),
[Apple connection options](https://developer.apple.com/documentation/uikit/uiscene/connectionoptions),
[continuous time including sleep](https://developer.apple.com/documentation/kernel/1646199-mach_continuous_time).

Platform references: [Flutter deep-link opt-out](https://docs.flutter.dev/ui/navigation/deep-linking)
and [Android App Link verification](https://developer.android.com/training/app-links/add-applinks).

## Sender creation boundary

`EntryShareSelectionService` projects the authenticated current snapshot returned
by `LocalCurrentEntryService`, not permissive legacy payload constructors. Native
fields are allowlisted per Entry type. TOTP, description, notes, billing address
and every custom field are off by default, regardless of Agent visibility. Native
labels are empty for UI localization; custom labels and selected values retain
their exact strings. Unsupported field types/values remain explicitly unavailable
and cannot be selected. Missing/duplicate custom identity fails without inventing
an ID. The full TOTP configuration is encoded as an `otpauth` URI only when its
fields are supported exactly; no silent algorithm/period/seed normalization is
performed. Script refs, execution policy, history and source keys are never copied.

`EntryShareCreationOptions` validates user form input: named email is the default,
additional protection is optional, password is 8–128 characters, PIN is 6–128 ASCII
digits, lifetime choices are 1/24/72/168 hours and the receipt limit is 1–100. Email
and receipt-count input are trimmed; protection secrets are deliberately exact.
Changing to anyone mode drops a stale email; choosing no protection drops a stale
secret. The explicit create serializer has no decryption-key or plaintext field.
The authenticated datasource exposes challenge/create POSTs with cancellation,
no redirects/no-store and redacted feature-level errors.

`EntryShareCreationCubit` binds its initial principal/organization/authorization
and memory-key generation. Source scope/revision is independently compared with
the requested Entry and session; the challenge revision must match before crypto.
The original mutable source maps are cleared even when a delayed read is rejected.
Crypto uses the challenge ID plus independent source scope and selected expiry.
An ambiguous create error retains one exact immutable request and key capability
in RAM. Only explicit retry reuses it; changed options or repeated taps cannot
issue another challenge or create a different ciphertext. Success drops the input
selection and protection request and returns the fragment once; disposal, explicit
clear or finite expiry removes it. Every await and error publication checks the
owning session. Late material is disposed instead of entering state.

`EntryShareCreationPage` opens from the list CTA as a separate root-navigator
page. The pinned primary action follows the shared form footer, while fields and
options scroll. EN/PL controls reuse AppScreen/AppBarTitle, OnboardingTextField,
AppDropdownField, AppToggle, WarningZone and PrimaryButton. The shared dropdown
now preserves the theme's font family. Sensitive field previews start masked;
changing the selected fields resets explicit preview confirmation. Email/PIN/
password validation is inline, and changing protection or recipient mode clears
the now-irrelevant controller. An uncertain POST removes editable plaintext
controls and offers only the original request retry. No additional page-view
event or secret-bearing route argument is introduced.

The page reads through `LocalCurrentEntryService.reveal(expected: ...)`, copies
the current private key and wipes it in `finally` and immediately on invalidation,
even when the reader is pending. Lock, account/key/permission change, background,
pop, covering the page and disposal discard draft controllers, reveal flags,
pending operations and the returned fragment. Resuming does not resurrect them.
A five-second foreground session check repairs authority changes; create/retry/
copy recheck immediately. Clipboard completion and failure revalidate before
publishing UI feedback. A negative widget test reproduced retaining the old link
on the clipboard error path after key replacement before this was fixed.

Only explicit Copy writes the full link through SecureClipboard's existing
45-second conditional clear. The full capability is not displayed, logged, sent
to analytics or persisted. It cannot be recovered after leaving the page. System
clipboard managers/cloud sync remain outside the application's deletion guarantee.
The covered sharing list suspends polling and refreshes after the form returns.

`PALLADIN_SHARING_WEB_ORIGIN` is a required, build-owned bare origin, empty by
default. `EntryShareLinkService` rejects credentials, paths, queries, fragments,
unapproved hosts and insecure non-local origins before opening the source. Stage
API requires the stage panel even with the production store identity; production
rejects the stage host. Local HTTP needs explicit configuration reachable from
the recipient device. Domain association/actual receiver deployment remains a
release prerequisite, not something inferred from a successful URL parser.

Tests cover native crypto roundtrip, identical retry, source substitution,
cancellation at read/challenge/crypto/POST, session replacement, expiry, the real
list CTA, foreground ownership, validation, optional PIN/OTP, opt-in Inbox,
keyboard layout and clipboard. Optional synthetic widget captures load a supplied
Inter font via `PALLADIN_SHARING_VISUAL_FONT` and write to
`PALLADIN_SHARING_VISUAL_DIR`; no font network fetch happens in normal tests.
390px light EN and 320px dark PL at 150% were inspected. These renderings and mock
transport tests do not prove physical-device behavior or actual HTTP delivery.

## Sender list and revocation

Entry Detail has a fifth Sharing tab, separate from Details, Agents, Logs and
History. `EntrySharingTab` owns its `EntrySharingCubit` and mounts no shared global
metadata cache. The authenticated `EntrySharingRemoteDatasource` calls the scoped
GET list and body-less DELETE routes; every request has a cancellation token and
disables redirects. JSON is decoded within the redacted feature boundary so
parser excerpts cannot reach shared transport logging. Neither route uses an
Entry/Vault encryption key or sends decrypted Entry content.

Cards distinguish delivery count/limit, first/last delivery and first display
confirmation. They show finite expiry, optional protection, notification choice
and stale-source warning. Unavailable timestamps display a dash; additive fields
and future server statuses/protection remain readable. Unknown statuses do not
enable a guessed mutation. All copy is EN/PL and shared theme/spacing tokens and
sheet controls are reused. Explicit revocation confirmation explains that old
copies cannot be recalled or an external password changed.

Only the visible foreground tab requests metadata, with 30-second repair and
explicit cursor pagination/retry. Background, tab departure, lock, account/key
replacement, permission loss and disposal cancel requests and drop rows and any
open confirmation. The Cubit binds its first valid principal/organization,
authorization generation and memory key generation. It checks that authority
before requests and before either success or failure can publish. A replacement
session cannot silently rebind an existing Entry surface. Revocation completion
re-fetches the list instead of inventing a server status. No plaintext persistence
or feature page-view analytics is introduced.

`entry_sharing_list_test.dart` uses real Dio request encoding with a test adapter,
controlled session/race tests and mounted widget interactions. It covers retry,
confirmation/cancel, active/background polling, unknown statuses and 320px EN/PL
layout including dark mode and 150% text. Two tests reproduced stale metadata
restoration on the error path after organization replacement before the fix.
Device visual review and real HTTP/API acceptance remain required.

## Independent encrypted snapshot

`features/vault/data/services/entry_sharing/EntryShareCryptoService` seals and
opens `palladin.entry-share.v1` using XChaCha20-Poly1305. Every preparation generates
an independent 32-byte encryption key, 32-byte access bearer and 24-byte nonce.
Neither source EntryDEK nor Vault key is an input. OTP and optional PIN/password
will be separate server gates, never encryption keys derived from a weak PIN.

The plaintext has exactly `schema`, `title`, `entryType` and `fields`. Each field
has exactly `id`, `label`, `type` and string `value`. Supported Entry types are
`key`, `credential`, `script`, `creditCard`; field types are `text`, `multiline`,
`concealed`, `totp`. Native field IDs retain their fixed types; custom IDs start
with `custom:`. Duplicate IDs, additional properties, empty selection and native
field type downgrade fail closed. This is validation of independently decrypted
input, not revalidation of backend-owned domain state.

The explicit serializer cannot include source policies, history, grants, keys or
Script references. The sender projector requires explicit field selection and
leaves TOTP, notes and all custom fields off by default. Values are never trimmed
or Unicode-normalized by this layer. Snapshot lists are immutable.

Nonce and ciphertext use canonical padded base64; ciphertext including its
16-byte tag is limited to 262,144 bytes. Decode bounds apply before native crypto.
Errors carry only `EntryShareErrorKind`, never parser/crypto diagnostics or input.

## Authenticated scope

The AAD is exactly **103 bytes**, with no separators or length prefixes:

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 19 | ASCII `PLDN-ENTRY-SHARE-v1` |
| 19 | 16 | Share UUID, RFC/network order |
| 35 | 16 | Organization UUID |
| 51 | 16 | Vault UUID |
| 67 | 16 | Entry UUID |
| 83 | 8 | Source revision, unsigned big-endian u64 |
| 91 | 8 | Expiry Unix seconds, unsigned big-endian u64 |
| 99 | 4 | Expiry fractional nanoseconds, unsigned big-endian u32 |

Revisions remain canonical decimal strings, including values beyond 2^53. UTC
expiry accepts up to nine fractional digits; fractions are encoded separately
from Dart DateTime to avoid microsecond truncation. Invalid normalized calendar
components are rejected. Equivalent fractional spellings produce identical AAD.
Sharing accepts canonical lowercase UUID versions 1–8; the pre-existing frozen
Vault-v2 UUID codec remains unchanged.

Creation scope must come from the selected authenticated organization/Vault/Entry,
its independently opened current revision, a matching server creation challenge
and the sender's chosen expiry. Reception receives the explicit canonical delivery
scope from the backend and independently compares the requested link's share ID.
Never derive expected scope from the same ciphertext wrapper being verified.
Changing any scope component (including one nanosecond) rejects authentication.

## RAM ownership

`EntryShareSecrets` owns wipeable key/bearer arrays. `dispose` zeros both and makes
the fragment serializer unusable. The exact fragment is
`#v=1&key={canonical-unpadded-base64url}&access={canonical-unpadded-base64url}`.
Aliases, reordering, duplicate/unknown fields, padding and nonzero unused bits are
rejected. No persistence API exists. Full URL validation belongs to
`EntryShareLinkService`; complete native ingress wiring/scrubbing remains
required work. The fragment parser does not itself install a
deep-link handler or authorize a host.

Crypto copies a borrowed decryption key before its first await and wipes that
copy, native SecureKey and plaintext byte buffer in finally paths. Failed
preparation also wipes newly generated key/bearer buffers. A successful caller
owns the returned capability and must dispose it on cancellation, expiry, lock,
account change or supersession. After every await the future lifecycle owner must
reject late results from an obsolete generation; byte-level cleanup alone does
not establish that ownership. Immutable Dart strings cannot be securely wiped;
drop all snapshot references when the owning flow ends. Never persist these
strings/keys, put them in route state, or send them to logs or analytics.

## Verification

`test/features/vault/entry_share_crypto_test.dart` loads native libsodium and
**fails**, rather than skips, if the library is unavailable. On macOS, provide
`PALLADIN_LIBSODIUM_PATH` for the test-host dylib; Linux uses `libsodium.so`.
Tests consume the same independently generated public fixture as web, check exact
AAD/decryption, and decrypt mobile-produced ciphertext with the fixture AAD.
Negative cases cover scope/key/nonce/ciphertext substitution, invalid authenticated
plaintext, byte limits, malformed encodings, UTF-8, field types and redacted errors.
See [fixture provenance](../../../test/fixtures/crypto/ENTRY-SHARE-PROVENANCE.md).

Real web↔mobile HTTP flows, public transport isolation,
limit=1 account/save continuation, physical-device Universal/App Links, visual
acceptance and the user test environment remain release gates.
