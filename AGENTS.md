@CLAUDE.md

# Codex Rules — Mobile

Read `CLAUDE.md` before changing this repository; it contains the app architecture, shared UI contracts, security rules, and build commands. All changes go through a PR and must pass `flutter analyze`, `flutter test`, and the relevant store build when signing or native projects are touched.

## System Password Manager / AutoFill

AutoFill on iOS and Android is MVP scope. The iOS `CredentialProvider` target is currently only a signed, embedded foundation: it requests user interaction and displays the localized locked state. It does not yet expose credentials. Full iOS behavior and Android Autofill Service are tracked by CVT-276.

For every password-manager integration:
- Preserve zero knowledge: plaintext credentials and encryption keys never go to the backend.
- Never persist MK, VK, private keys, decrypted payloads, passwords, or TOTP seeds in App Groups, SharedPreferences, files, logs, analytics, or extension caches.
- Require OS/user authorization before decrypting or returning a credential; locked state fails closed with `userInteractionRequired` or the Android equivalent.
- Normalize and verify the requested domain/service before returning a credential. Ambiguous or mismatched requests must be rejected.
- Any shared keychain/keystore access-group design requires an explicit security review; do not infer sharing from bundle identifiers.
- Keep native extensions/services thin, reuse the established client-side crypto contract, and wipe temporary sensitive buffers.
