# Current Member Entry Sync v2 fixtures

These files are copied byte-for-byte from `palladin-protocol` commit
`f0d1563cf04eb790b5b8e3b28f974a6301338100`:

- `manifest.json`
- `vectors/valid-snapshot.json`
- `vectors/tombstone-reset.json`

The frozen source paths are under
`contracts/vault-v2/fixtures/current-member-entry-sync-v2/`.

CVT-690 local deviation: the two vector files replace the wire value
`"memberX25519"` with the algorithm-neutral `"memberEncryption"` (the backend
renames JSON enum values in lockstep, with no compatibility layer). No other
byte changed. Re-vendor from `palladin-protocol` once its vault-v2 fixtures
carry the neutral names, and remove this note.
