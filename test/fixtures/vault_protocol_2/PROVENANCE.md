# Vault protocol 2 fixture provenance

This directory is a deterministic, synthetic test-data snapshot derived from
the source identified below. It is consumed directly by the Flutter test suite
and is not included in production assets.
Running the tests requires only this repository; no parent monorepo, private
package, network request, or external fixture checkout is used.

## Exact source

- Source repository identity: `Palladin-io/palladin`
- Source commit: `b370b56e4f65ecf5350bc4f9203fee6429572955`
- Source path at that commit: `contracts/vault-v2/fixtures/v2`
- Generator recorded by the source manifest: `fixtures/v2/generate.mjs`
- Source manifest SHA-256:
  `13c43defd459e95d50bf2f0a76a5a5446ca41903c36a38beef8b8af3aa208050`
- Vendored manifest SHA-256:
  `b3cbd9bee6a663789fae4047931e411abb3ad0c15fa2204a747be6c09b54fd9e`

The source repository is provenance metadata, not a build or test dependency.
The committed manifest pins every included JSON file, and the Flutter test
verifies the manifest digest before checking each file digest and executing the
vectors.

## Public-sanitization delta

The source `member-vault-metadata` vector contained an internal tracker label
inside its synthetic description. The vendored public snapshot replaces that
description with `Synthetic protocol fixture` and deterministically recomputes
`plaintextHex` and the XChaCha20-Poly1305 ciphertext using the source fixture's
unchanged key, nonce, and AAD. No production material is involved.

The source `vectors/envelopes.json` SHA-256 before this one documented change is
`bb642e737fda2c77e89f181b342bf9c24c6bc3dbfeafe0ebd38af1f3041e9a62`.
The vendored file digest appears below, and the manifest records the same delta.
All other vector files are byte-for-byte copies of the identified source.

## Snapshot contents

```text
825def1e19c0d012b83c2736a9cc9428d248bc4a78f9ad0a5b04a34e4c1dd904  vectors/aad.json
c6b590dcb49cd58542d3b3d9979743bd35a1f256ca692e369357d513fae888c8  vectors/key-derivation.json
a6e0309b31c6b66c5d1f24adabf88a8e4018886891ec803af5359902be49f627  vectors/envelopes.json
2b9fa47e377e92a5c7d5a9299761ca42dc12f2024bef736ef372be3a16ca840a  vectors/signatures.json
d4f7d8a586cacf53896f9fe609163a88cc292646f3d010bb807a7d1cfc215ec8  vectors/pairing.json
b01e5cad49347520294b2c3adc921181db936f58d847101e09e6a2cfc5d310f1  vectors/rotation.json
2368188c7a0b686eac105c252527b0e6e8c6434f1d326eb00868f57869c30c8e  negative/corruption.json
```

All payloads are synthetic. Deterministic nonces and sealed-box ephemeral seeds
exist only to make protocol expectations reproducible; production code must use
cryptographically secure random values.

## Updating the snapshot

Fixture updates are protocol changes, not routine test refreshes:

1. obtain the approved fixture output for a specific source commit;
2. verify the source manifest and generator output independently;
3. replace the unchanged vector files byte-for-byte and reapply the documented
   public-sanitization delta to the metadata vector;
4. update the source commit, source path, manifest digest, and file digests in
   this document;
5. run the full Flutter suite, which validates the vendored bytes without
   accessing the source repository.

Contributors who do not have access to the source repository can still build,
analyze, and run every test against the checked-in snapshot. They should not
attempt to regenerate or alter normative protocol vectors without a reviewed
protocol update.
