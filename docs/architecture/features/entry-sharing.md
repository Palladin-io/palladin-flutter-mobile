# Individual Entry sharing — CVT-644 (in progress)

The mobile snapshot crypto boundary, sender list/revoke tab and creation page
are implemented on the feature branch. The isolated guest transport and reception
Cubit are tested foundations, not yet connected to receiver screens. Save-copy/
account continuation, native ingress and Inbox/audit remain pending. Local tests
are not evidence of deployed end-to-end sharing.

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
and drops the recipient token and plaintext references. The page must still wire
background, lock, account/permission/key changes, route departure and immediate
revalidation; having the Cubit alone does not establish those UI boundaries.

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
not a fallback plaintext path. A 15-minute local RAM ceiling starts when the Cubit
takes ownership and can only shorten to session expiry. Both wall and monotonic clocks
are checked before actions and after awaits, so clock rollback or delayed timers
cannot extend it. Invalid/unusable expiry fails closed for this local secret
lifetime boundary. Immutable Dart strings can be dropped, not securely zeroed.

Tests cover 19 actual loopback-HTTP cases and 24 reception/native-crypto cases:
all request contracts, redirects/cookies, malformed/oversize bodies, cancellation
before/after headers, optional gates, exact retry, separate ACK, concurrency,
scope substitution, delayed crypto and both success/error after owner changes.
The loopback server is a synthetic fixture, not the Palladin API or real email
provider. Screen mounting, auth/save continuation and device E2E remain required.

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
rejected. No persistence API exists. Full URL/domain validation and native ingress
scrubbing remain separate required work; this parser does not itself install a
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
