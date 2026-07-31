# Vault protocol 2 fixture provenance

This directory is a byte-for-byte snapshot of deterministic, synthetic test
vectors from the public Palladin protocol repository. It is consumed only by
the Flutter test suite and is not included in production assets. Tests require
no parent monorepo, private package, network request, or external checkout.

## Exact source

- Source repository: `Palladin-io/palladin-protocol`
- Source commit: `6f39860acc680cec3318e9cdf2eeaeb55be77532`
- Source path: `contracts/vault-v2/fixtures/v2`
- Generator: `fixtures/v2/generate.mjs`
- Manifest SHA-256:
  `899ac3f9a5f9dbb00cae3c53c361ab1af34a27ed88a2bc517cd7891332d0a33c`

The committed manifest pins every included JSON file. The Flutter tests verify
the manifest digest, each file digest, and the cryptographic vectors without
accessing the source repository.

## Snapshot contents

```text
7731c54ed36c4375745193ebeba159ce21644c562b077379852b476f55839b0c  vectors/aad.json
c77e9e5a62bcd1ffae37f48f3a7feadd4e0c7945569353fb5adc980051da7d24  vectors/key-derivation.json
155cd388f33772614a02d28e0b22a2dbf637d5f9c96d3d153354b6c3f8385d0f  vectors/envelopes.json
dd92600a5f812ba88bac537a111a4eaeeb36deca835cae41536af0d8b32ae09d  vectors/signatures.json
738413fb48af51fed2cfa172a67b93f01ad41fa98c72d46969a7def6a103688f  vectors/pairing.json
7e7f5351781e1811a320d82e828dc8f4d37beb549ad5909efae9e26c89ab7612  vectors/rotation.json
577ba27ef7a2039d08dcb3afbc1975905aaa821811c2ac73b430173fb008f866  negative/corruption.json
```

All payloads are synthetic. Deterministic nonces and sealed-box ephemeral seeds
exist only to make protocol expectations reproducible; production code must use
cryptographically secure random values.

## Updating the snapshot

Fixture updates are protocol changes, not routine test refreshes:

1. regenerate and review the fixtures in `palladin-protocol`;
2. copy the approved fixture output byte-for-byte;
3. update the exact source commit and manifest digest above;
4. run the complete Flutter conformance and application test suite.

Contributors can build, analyze, and test the app entirely from this repository.
