# Entry sharing fixture provenance

`entry-share-v1.json` is byte-identical to
`src/shared/crypto/fixtures/entry-share-v1.json` in
`Palladin-io/palladin-react-web-panel` at commit
`ffaf08c3846d5dd80a495cb116b1a72fbb941109`.

SHA-256: `a5c219fd38acf08f060cd04487c9e88f666c039800ebb2753074587c8445cf41`.

The source fixture was independently generated on 2026-09-20 using Python
`uuid`/`struct` and native libsodium, not either client encoder. All identifiers,
keys, nonce and credential content are synthetic public test material. Revision
`9007199254740993` and nine-digit fractional expiry detect lossy number/time
conversion. The literal AAD is 103 bytes, starting with the 19-byte ASCII domain.

Tests run entirely from this repository; no sibling checkout, private resource,
network request or production credential is required.
