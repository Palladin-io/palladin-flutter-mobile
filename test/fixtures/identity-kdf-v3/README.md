# Identity KDF v2/v3 fixtures

Byte-identical copies from `Palladin-io/palladin-protocol` at commit
`dadcd0f3649178531f8c102ea041b3aa006c721f` (palladin-protocol PR #18):

| File | Source | SHA-256 |
|---|---|---|
| `v2-derivation-vectors.json` | `contracts/identity-kdf/v2/derivation-vectors.json` | `5607da6ce0722f82b75d3a8d05dc01b4849eb10814cb4d1718cb97a0358df6eb` |
| `vectors.json` | `contracts/identity-kdf/v3/vectors.json` | `f990fbc005e6df610aa24213e2dbdaee12fd8d3f747d944e157e9f8990b820c3` |

All values are deterministic synthetic test data. Update the protocol fixture
first, then vendor the same bytes here.
