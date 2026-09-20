# Individual Entry sharing — CVT-644 (in progress)

The mobile snapshot crypto boundary and sender list/revoke tab are implemented
on the feature branch. Creation and guest receiver screens, the remaining HTTP
lifecycle, save-copy/account continuation, native ingress and Inbox/audit are not
yet connected. Local tests are not evidence of deployed end-to-end sharing.

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
Script references. The future sender projector must still require explicit field
selection and leave TOTP, notes and all custom fields off by default. Values are
never trimmed or Unicode-normalized by this layer. Snapshot lists are immutable.

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

Real web↔mobile HTTP flows, sender field projection, public transport isolation,
limit=1 account/save continuation, physical-device Universal/App Links, visual
acceptance and the user test environment remain release gates.
