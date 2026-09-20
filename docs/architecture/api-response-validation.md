# API response boundaries

Authenticated, version-matched Palladin REST responses are decoded into typed
models. The backend owns lifecycle transitions, capacity, pagination sizes,
status relationships and metadata formats. Do not reject a list or silently
remove a row to re-enforce these server rules. Contract drift belongs in
provider/consumer tests before release.

## Display and transport

- Grant history preserves future type/status values as `unknown`; it never
  guesses a known grant scope or labels an unknown lifecycle as revoked.
  Unsupported grant types cannot enter a known re-grant producer.
- Pending grant rows remain visible when the reason envelope is unavailable.
  Only the explicitly opened review authenticates the reason and its binding
  to the request. Missing reasons cannot be reviewed or approved.
- Search preserves unknown server types as display-only results; they never
  acquire Entry/Vault navigation, secret reveal or approval capabilities.
- Inbox already maps future categories to history. Push/SignalR accepts future
  category strings so the authoritative Inbox refresh still occurs. Its
  value-free four-field transport allowlist remains in place.
- Vault member pages and administrative search do not repeat requested row
  limits as response assertions. Rotation pending-list and Vault-list display
  pages likewise accept the server's full response.
- Catalog batches retain usable icons when another item has no usable URL,
  omitted output or an unknown lifecycle. HTTP(S) delivery URL and public
  hostname checks remain independent network boundaries. Icon preparation retries
  only explicit pending outcomes, so unknown or omitted results cannot stall
  an import. WebsiteIconService uses only assets explicitly reported ready for
  save/import; pending metadata remains available to the mapper without becoming
  a usable icon. Empty optional catalog identities are omitted at the Vault
  plaintext serialization boundary to avoid producing unreadable ciphertext;
  this does not discard response rows or reintroduce API lifecycle assertions.
- Ordinary settings, organization, roles, invitations, preferences and Entry
  history responses already deserialize without repeated business validation.

## Retained independent boundaries

Crypto services still verify protocol/suite, signature, complete envelope
structure and independently authenticated organization/Vault/Entry/principal,
grant, key-version, epoch and revision bindings before using keys or plaintext.
Changing metadata tolerance does not weaken these checks.

Member-sync response wrappers accept additive fields and .NET timestamps with
nine fractional digits. Required transport fields, known sync item operations,
offline authority version/lease policy, finite lease expiry, monotonic cursors,
byte/item/device limits and authenticated envelope bindings remain enforced.
Future Entry lifecycle metadata maps to an unknown display state without
rejecting the authenticated generation; it is never promoted to active for
autofill, secret actions or export.
The latter protect persisted ciphertext generations and bounded device work,
not a duplicate authorization decision. Additional metadata is not persisted.

Rotation's cryptographic plan, key epochs, fencing token and prepared material
continue to be checked against the listed plan/current session; key/profile and
source-page preparation budgets remain bounded. User input, file import,
decrypted protocol payloads, Script parameter contracts and third-party/native
messages remain independently validated.

Individual Entry sharing accepts additive recipient metadata and preserves
future mode/protection values for presentation; unknown gates never enable an
unsupported operation. Its isolated public transport bounds metadata to 16 KiB
and ciphertext delivery JSON to 512 KiB before decoding to protect device memory.
Reception limits secret residence to a local 15-minute monotonic/wall lifetime,
shortened by server session expiry. This is a local capability-lifetime boundary,
not a reimplementation of backend lifecycle rules. Decryption independently binds
the requested share ID to canonical delivery authority and authenticated AAD.
See [Entry sharing](features/entry-sharing.md) and its negative transport/Cubit
tests for scope substitution, expiry, owner replacement and oversized streams.
