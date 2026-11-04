# security_upgrade

In-place migration of a security-version-1 account (`identity-kdf/v3`
`migration`) on its first unlock by this release.

- **Start:** `UnlockCubit` emits `UnlockSecurityUpgradeRequired` with a
  `FreshSecurityUpgrade` (password, account, old member key in memory) after a
  version-1 password unlock, or a `ResumedSecurityUpgrade` after a version-2
  unlock whose account still returns `legacyMemberKey`. The biometric shortcut
  cannot start an upgrade. The page route `/security-upgrade` is reachable
  only with that in-memory start and is non-dismissable.
- **Commit:** `SecurityUpgradeService.commit` builds the version-2 material
  (`AccountKeyMaterialService`), wraps the old member key under the new master
  key, stores the new Secret Key on the device **before** the atomic
  `POST /api/account/security-upgrade` (idempotent by `migrationId`, reused for
  retries), so a lost response or crash never strands the account.
- **Re-wrap:** every member Vault key still sealed with the old suite is
  opened with the old key and sealed to the new X-Wing member key (same Vault
  key version and member generation) via
  `PUT /api/vaults/{id}/members/me/key-envelope`. When the key-migration report
  shows none pending, the legacy key record is deleted.
- **Then:** new recovery phrase (three-word confirmation), Emergency Kit,
  done. The biometric copy of the old master key is cleared.
- Network errors stop at the current step; Retry continues without repeating
  finished work. No algorithm names are shown.

Known limit: a crash after the commit but before the phrase confirmation
leaves a recovery phrase the user never saw; the Emergency Kit can still be
saved from Settings.
