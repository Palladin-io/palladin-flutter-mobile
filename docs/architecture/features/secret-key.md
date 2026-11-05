# secret_key

Secret Key (Identity security version 2 Account Secret) on this device and
device-to-device transfer (`identity-kdf/v3` `devicePairing`, protocol 2).

- **Storage:** `AccountSecretStore` (core) keeps the trusted-device copy:
  this-device-only, non-synchronizable Keychain item on iOS; Keystore-backed
  EncryptedSharedPreferences excluded from backup and transfer on Android.
- **Data:** `SecretKeyTransferRemoteDatasource` is an opaque relay. Only public
  keys, server challenges and ciphertext cross it. Errors are the typed
  `SecretKeyTransferErrorKind`; presentation maps them to
  `DeviceTransferFailure`.
- **Crypto:** `DevicePairingCrypto`, `PairingOffer`, `PairingQr` and
  `SecretKeyCodec` in `lib/core/crypto/identity/`. Feature code never names the
  algorithm.

## Approve a device (sender)

`DeviceTransferSenderCubit` + `DeviceTransferApprovePage`
(`/settings/add-device`, Settings › Security › Devices; unlocked shell only).
The phone scans the new device's `palladin-pair:v2:r:` code, reads the session
from the backend and builds the offer with `PairingOffer.verify`:

- The digest of the recipient key served by the backend must equal the digest
  in the scanned QR; a substituted key creates no offer and the session is
  cancelled.
- Both devices show the same SAS. The Secret Key is read from the store and
  sealed only after the user taps Approve, and the buffer is wiped afterwards.
- Reject cancels the session. Expired, consumed and unknown sessions show
  "Code expired".
- A computer's `palladin-pair:v2:s:` code scanned here shows "Wrong code" and
  tells the user to scan it on the new phone.

The phone does not show a sender code itself; the web panel provides that
mode.

## Get the Secret Key (recipient)

`SecretKeyAcquisitionCubit` + `SecretKeyAcquisitionPage`
(`/secret-key/acquire`, reachable with or without a session) receives
`SecretKeyAcquisitionArgs(accountId, email)` from the sign-in bootstrap and pops
a fresh copy of the 32-byte Secret Key, or `null`. The caller owns and wipes
the returned buffer; the cubit wipes its own copy and the recipient seed on
close.

- **Show a code:** a fresh in-memory recipient key, `createAsRecipient`, QR
  `palladin-pair:v2:r:`, SAS, then `claim` polling for at most 300 s.
- **Scan a computer code:** `palladin-pair:v2:s:` supplies the transfer id and
  the challenge; the phone attaches its key with `attachRecipient`. The
  challenge in the SAS and envelope transcript is the scanned one, not a
  backend value.
- The claimed `accountId` must equal the bootstrap account, and the envelope
  must authenticate against the local transcript; otherwise nothing is
  returned.
- The phone has no action while the computer decides; the screen says to
  approve on the computer if the codes match. A scanned `v2:r:` code shows
  "Wrong code" and points to Add a device on a signed-in phone.
- Once the key is available the page shows "Secret Key received" for about a
  second, then pops; the key is saved only after the sign-in it unlocks
  succeeds.
- **Emergency Kit:** typed `PSK2-…` (checksum bound to the account) or the kit
  QR (`palladin-kit:v1:`, account id must match).

Camera scanning goes through the injectable `QrScanLauncher`
(`TransferQrScannerPage` by default), so widget tests never start the camera.
The scanner is always dark, uses `AppBarTitle` and draws a visual-only scan
frame; decoding still covers the whole preview.
A wrong Secret Key is detected only by a failed sign-in.
