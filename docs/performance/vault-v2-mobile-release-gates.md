# Vault v2 mobile performance release gates

CVT-472 separates deterministic CI gates from physical-device release
measurements. CI must not turn host or simulator wall-clock observations into a
claimed low-end-mobile latency budget.

## Deterministic CI evidence

`flutter test test/performance/vault_v2_mobile_structural_budget_test.dart`
checks the canonical workloads at 1,000, 10,000, and the mobile plan maximum of
20,000 Entries:

| Workload | Structural gate |
|---|---|
| Initial Member sync / unlock | MemberIndex heads only; zero MemberSecret and zero history rows |
| Snapshot pagination | 100 requested items; responses above the protocol ceiling of 200 are rejected |
| Incremental sync | Exactly 1% of the representative Entry count |
| Decryption | At most two concurrent MemberIndex decrypts |
| Logical in-flight ciphertext | `2 × (32,768-byte MemberIndex + 48-byte EntryKey wrapper)` |
| Local search | At most 20,000 runtime candidates; result limits remain feature-owned |
| Grant approval | Exactly one current canonical MemberSecret opened on demand |
| History | 20 rows per cursor page, at most 100 rows loaded, never in initial sync |

The structural regression string contains only counts, limits, and logical byte
estimates. It must never include labels, queries, ciphertext, decrypted fields,
opaque resource IDs, or timings tied to content.

The envelope service independently enforces authenticated ciphertext ceilings:
32,768 bytes for MemberIndex, 48 bytes for an EntryKey wrapper, and 262,144 bytes
for MemberSecret and GrantPayload. The CI byte figures are logical upper bounds;
they are not heap profiler measurements.

## Physical low-end release artifact

A production release remains blocked until a named, weakest-supported physical
iOS device and Android device have a retained benchmark artifact containing:

- app commit, release flavor/build mode, OS version, device model, and thermal
  state;
- cold snapshot/unlock, exact 1% delta, local search, grant approval, one lazy
  detail, 100-version history list/decrypt/diff/restore, and planned rotation;
- p50/p95 wall-clock latency, peak resident memory, CPU, and network bytes for
  every workload and representative Entry count;
- ciphertext counts and sizes only in regression output; no secret content,
  labels, search queries, resource IDs, or content-derived timing dimensions.

The baseline and allowed regression percentages must be approved from those
measurements. Until that artifact exists, the physical-device p95 gate is
explicitly **unverified and release-blocking**; CI success does not waive it.
