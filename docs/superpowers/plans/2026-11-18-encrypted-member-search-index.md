# Encrypted Member search index implementation plan

Goal: reopen persisted authenticated search metadata after unlock without per-Entry key unwrap/index decrypt. User approved this design in the current conversation; implement through TDD.

Architecture: disposable, encrypted, bounded per-Vault chunks in the canonical SQLite cache. Keep canonical ciphertext as source of truth. Persist metadata only; reuse the existing protected unlock and Vault-key authority. Authenticate chunk completeness and version against current canonical state. Lock clears plaintext RAM, not ciphertext. Selected secrets and final origin/lease/revocation guards remain independent.

Constraints: no plaintext metadata/keys/secrets on disk or in logs; no new backend crypto format; no full-body scan for legacy usernames; no iOS publication. Existing explicit CI/review/release authorizations remain subject to repository gates.

- [x] RED: cold reopen after lock currently opens every Entry key/index; assert zero such calls for a valid persisted index.
- [x] Codec: authenticated purpose-separated bounded metadata chunks; roundtrip, wrong scope/key, corruption, missing/replayed chunk, empty index tests.
- [x] SQLite: atomic canonical-state/index publication; partial changed-chunk writes, interrupted commit, missing/corrupt derived data, migration and purge/quarantine tests.
- [x] Member sync: snapshot/closing delta, insert/edit/archive/delete, lease/key/member changes, reset, offline, concurrent lock/account replacement and selected-read tests.
- [x] iOS provider readonly integration tested; no claimed parity from Dart-only tests.
- [x] Measure cold rebuild/reopen/warm and changed-one-record with real crypto/SQLite and synthetic data; report crypto/network counts, not inferred S22 latency.
- [ ] Required local checks, security review, PR and authorized review/CI before any release.

Checkpoint: branch feat/encrypted-member-search-index, based on reviewed prior AutoFill implementation. Build12 remains installed; no new build or release made. Regression RED observed before production changes. Full Flutter suite2605 passed/2 skipped; analyzer clean. Host1024 entries reopen40.593ms vs missing-index299.378ms (not phone latency). Awaiting PR/cloud review; no new build.
