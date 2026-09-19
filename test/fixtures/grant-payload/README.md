# GrantPayload contract fixture

`v1/vectors.json` is an exact vendored copy of
`palladin-protocol/contracts/grant-payload/v1/vectors.json` at commit
`e2214d2971c5b8c1f4631f296936388c8aa4465d`.

Do not edit the local vector independently. Update the public protocol contract
first, then vendor the same bytes into every producer and consumer.

## V2 operation-time TOTP

`v2/registry.json` and `v2/vectors.json` are byte-identical public files from
`Palladin-io/palladin-protocol`, source commit
`5783fc4f5578981ba22326c3b28de13e6a5839bc` (merged via protocol PR #14).
The seeds are public RFC 6238 / synthetic boundary test data, never accounts.

SHA-256:
- registry: `45fb5f68ed7170f2d1ea840ead308950375bdc60c6c8ed9036c3cdea8faa07db`
- vectors: `4c321c375be8b35ea22a34deae375f96e0a69e8f50515a87e7fd0a79ec00ad73`

Eight positive vectors prove canonical payload bytes and operation-time code
outputs; fourteen invalid-source vectors enforce the closed protocol boundary.
V1 fixtures stay unchanged for Script packages and legacy compatibility.
