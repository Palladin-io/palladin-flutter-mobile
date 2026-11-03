# AutoFill v3 bridge contract (implementation contract)

All operations use `io.palladin.mobile/autofill`. v2 methods remain supported for compatibility, but v3 consumers must not silently downgrade a partial update to v2. Existing origin matching is unchanged. Fixtures and plaintext examples contain synthetic data only.

## Values

- Base: `{ "generation": positive integer, "revision": positive integer }` (native session generation + catalog revision).
- Entry coordinate: `{ "vaultId": nonempty string, "entryId": nonempty string }`; organization is independently fixed by the manifest/session.
- Manifest: same fields as `AutoFillCacheManifest.toPlatformMap()`. Unlike v2, empty `vaults` and empty Vault `entries` are valid complete snapshots; they do not imply missing native state.
- Record: same fields as `AutoFillRecord.toPlatformMap()`.
- Writer epoch: positive integer, app-process-only native holder, never a key.
- Deny token: nonempty opaque native-issued string, owning exactly its denied coordinates; a different owner cannot release it.

## Methods

`beginWriterSession({sessionToken}) -> writerEpoch`

Starts a new ephemeral app writer epoch for the active provider generation. Does not retrieve the protected provider opening key. Writer key is initialized by full publication. Prior epoch invalid immediately.

`endWriterSession({writerEpoch}) -> null`

Synchronous native invalidation/wipe of matching writer epoch, bypassing queued writes. Does not revoke provider read generation. A stale end request must not clear a newer writer.

`replaceCacheV3({sessionToken, writerEpoch, base?, releasingDenies: [], payload: {version: 3, manifest, records}}) -> base`

Publishes complete records and current authority, initializes fresh dedicated writer key and biometric protected provider opening key. Atomic authenticated catalog/fence commit; checked writer epoch immediately before commit. Empty complete cache returns a valid base, but has no provider suggestions. Replacement of an existing verified catalog requires its exact base and owned denial tokens; unknown owners cannot be erased. Missing/corrupt catalog or lost writer requires the caller to commit the existing global clear under authoritative repair gates before beginning a new writer and full initial publication.

`denyEntries({base, writerEpoch, entries: [coordinate]}) -> {base, denyToken}`

Exact-base CAS (including an empty coordinate list), persistent scoped denial and new catalog revision. Acknowledged before remote mutation. Existing picker from older revision must fail final handoff. Missing writer/base is a typed recovery condition requiring global deny before remote mutation; if global deny fails, remote mutation must not start.

`applyCacheDelta({base, writerEpoch, manifest, upserts: [record], removals: [coordinate], releasingDenies: [denyToken]}) -> base`

Exact-base CAS. Manifest is COMPLETE current eligible authority, not only changed entries. Preserve unchanged ciphertext only when complete independent authority and immutable record revision/key/scope match, with effective expiry no later than original record AND current authority lease. Denial may be released only for matching native owners and reconciled coordinates. Unknown/duplicate tokens and conflicting upsert/removal coordinates fail. Never install a delta on missing or unverified base. Never implicitly reactivate a denied generation. Record body encryption/decryption count must be O(changed entries), not O(total entries).

## Failure codes

- `AUTOFILL_FULL_RECOVERY_REQUIRED`: missing/incompatible/expired/quarantined base, missing writer key. No success acknowledgment; caller must use existing authoritative full-repair/deny gates.
- `AUTOFILL_STALE_BASE`: CAS mismatch. No mutation; caller must not treat the submitted delta as a snapshot.
- `AUTOFILL_WRITER_INVALIDATED`: stale/locked writer epoch; no commit and no key retained.
- `AUTOFILL_CACHE_ERROR`: invalid scope/authority/input or persistence/crypto failure; no sensitive error details.

The Dart publication methods require a local synchronous guard callback, invoked after bridge availability awaits and immediately before channel submission; it is never serialized. The publisher rechecks it after acknowledgement before updating its base, owned tokens or readiness.

Native providers never read through writer holder. Biometric key retrieval and exact origins remain mandatory. Every selected credential binds generation+catalog revision and checks original/current effective lease, deny state and clock under existing mutation authority (Android monitor; iOS process flock plus lock).

## iOS identity acknowledgment

The returned base is acknowledged only when guarded identity maintenance has completed for that catalog revision. Use incremental identity save/remove when supported; fallback uses COMPLETE encrypted catalog identity projection, never delta-only records. Stale callbacks/compensations cannot erase or acknowledge newer identities. Catalog commit remains authoritative even if identity maintenance fails; readiness stays failed and recovery reconciles identities from the catalog.
