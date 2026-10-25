# Android session continuity and biometric opt-in

Accepted scope: preserve existing installed sessions, remove enrollment prompts
from login/password unlock, offer explicit Enable / Not now on Home and later
setup/disable in Security. Retain strong protected-key storage and cleanup.

## Evidence and design

Pinned flutter_secure_storage 9.2.4 migrates legacy SharedPreferences entries
into EncryptedSharedPreferences and removes the originals. Production session
storage used the default backend while biometric marker calls selected the
encrypted backend. A marker read/write therefore made subsequent legacy token
and user-ID reads empty. Use one constructor configuration across DI and all
entry points; plugin migration preserves the legacy session without biometric UI.

Explicit setup uses the authenticated in-memory MK, a temporary wiped copy and
the existing cleanup generation fence. Only the nonsecret per-account dismissal
is persisted in SharedPreferences. Cancellation leaves authentication unchanged.

## Checkpoint

- Worktree: `.worktrees/android-biometric-opt-in`, branch
  `fix/android-biometric-opt-in`, based on main `8998bffc…2a50f8`.
- RED: storage migration regressions returned null session metadata; login test
  observed unwanted enrollment. GREEN: focused storage/login/unlock/setup/card
  suite 27 tests; analyzer clean. No native Android device is attached.
- Production AuthRepository/AuthBloc/router regression: old constructor RED
  (`/login` instead of `/unlock` after marker access), fixed configuration GREEN.
  This is native-storage contract simulation, not OS device proof.
- Parent owns final integrated suite, Codex review, merge and release.
- Remaining acceptance: Samsung upgrade, explicit enrollment/cancel, lock/unlock,
  logout and re-enrollment on the tester build. No device success is claimed.
