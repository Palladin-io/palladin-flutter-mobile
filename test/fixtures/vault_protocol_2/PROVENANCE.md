# Vault protocol 2 fixture provenance

This is the minimal byte-for-byte snapshot needed by Flutter's native protocol
tests. It is test data only and must never be bundled as a production asset.

- Canonical repository: `Palladin-io/palladin`
- Canonical root commit: `b370b56e4f65ecf5350bc4f9203fee6429572955`
- Canonical path: `contracts/vault-v2/fixtures/v2`
- Manifest SHA-256: `13c43defd459e95d50bf2f0a76a5a5446ca41903c36a38beef8b8af3aa208050`

The manifest pins every included JSON file. The Flutter test verifies the
manifest digest and then verifies every file against its manifest entry before
running any vector. Current file digests are:

```text
825def1e19c0d012b83c2736a9cc9428d248bc4a78f9ad0a5b04a34e4c1dd904  vectors/aad.json
c6b590dcb49cd58542d3b3d9979743bd35a1f256ca692e369357d513fae888c8  vectors/key-derivation.json
bb642e737fda2c77e89f181b342bf9c24c6bc3dbfeafe0ebd38af1f3041e9a62  vectors/envelopes.json
2b9fa47e377e92a5c7d5a9299761ca42dc12f2024bef736ef372be3a16ca840a  vectors/signatures.json
d4f7d8a586cacf53896f9fe609163a88cc292646f3d010bb807a7d1cfc215ec8  vectors/pairing.json
b01e5cad49347520294b2c3adc921181db936f58d847101e09e6a2cfc5d310f1  vectors/rotation.json
2368188c7a0b686eac105c252527b0e6e8c6434f1d326eb00868f57869c30c8e  negative/corruption.json
```

## Updating the snapshot

1. A protocol-version decision must first approve any canonical fixture change.
2. Check out the approved root commit and run the root fixture generator and
   validator.
3. Replace only the eight JSON files in this directory with exact copies from
   the canonical path; do not translate or regenerate expectations in Dart.
4. Update the root commit, manifest digest and file digests above.
5. Run this repository's fixture test once from the vendored default and once
   with `PALLADIN_VAULT_V2_FIXTURES` pointing at the root checkout; both runs
   must pass byte-for-byte.
