# security_upgrade

In-place migration of a security-version-1 account (`identity-kdf/v3`
`migration`) on its first unlock by this release.

- **Start:** `UnlockCubit` emits `UnlockSecurityUpgradeRequired` with a
  `FreshSecurityUpgrade` (password, account, old member key in memory) after a
  version-1 password unlock, or a `ResumedSecurityUpgrade` after a version-2
  unlock whose account still returns `legacyMemberKey`. The biometric shortcut
  cannot start an upgrade. The page route `/security-upgrade` is reachable
  only with that in-memory start and is non-dismissable.
- **Phrase first:** a fresh upgrade shows the new recovery phrase and asks
  for three words before anything is committed, so a crash can no longer leave
  a phrase the user never saw.
- **Commit:** `SecurityUpgradeService.commit` builds the version-2 material
  (`AccountKeyMaterialService`) from the confirmed phrase, wraps the old member
  key under the new master key, stores the new Secret Key on the device
  **before** the atomic `POST /api/account/security-upgrade` (idempotent by
  `migrationId`, reused for retries), so a lost response or crash never
  strands the account.
- **Re-wrap:** every member Vault key of the session's organization still
  sealed with the old suite is opened with the old key and sealed to the new
  X-Wing member key (same Vault key version and member generation) via
  `PUT /api/vaults/{id}/members/me/key-envelope`.
- **Vault Agent message keys:** a member with `VaultManage` migrates every
  Vault whose response names a non-active `vaultAgentMessageKeySuiteId`
  through `AgentMessageKeyMigrationService`:
  `POST api/vaults/{id}/key-rotations/agent-message-key-migration` → claim →
  one batch (new X-Wing private key under the unchanged VK, the public anchor
  with `schemeId` = suite, successor manifests signed with
  `vaultAgentMessageKeySuiteId`) → commit. 409 means already current; a 403
  Vault stays for its managers; Agents still on a read-only key are skipped.
- **Clean-up:** the legacy key record is deleted only when the key-migration
  report shows `accountMemberEnvelopesPendingRewrap == 0`. Organizations in
  `organizationIdsPendingRewrap` resume on the next unlock there (mobile has
  no organization switcher); an unlock in an organization with nothing left
  skips the screen.
- **Then:** Emergency Kit (fresh upgrades), done. The biometric copy of the
  old master key is cleared.
- Network errors stop at the current step; Retry continues without repeating
  finished work. No algorithm names are shown.
