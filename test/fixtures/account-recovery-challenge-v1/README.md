# Account recovery challenge fixture

`vectors.json` is byte-identical to
`src/fixtures/account-recovery-challenge-v1/vectors.json` in
`Palladin-io/palladin-crypto` at commit
`80b1a5c5fc6c60329a886795eafdf0915cb8ed33` (palladin-crypto PR #33).

SHA-256: `f6512e00fcf5c508138cbf51776aaa72b21b1a6d3f3e1d5d50bebeba8440d327`.

The vectors were generated with native libsodium by
`scripts/generate-account-recovery-challenge-vectors.mjs`, independently of
the client implementations. All keys, identifiers and secrets are synthetic
public test material. Update the source fixture first, then vendor the same
bytes here.
