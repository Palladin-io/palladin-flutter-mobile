# Member preparation loopback benchmark

Debug-only, synthetic workload for comparing the former serial Vault loop with
production `MemberIndexPreparationService` batch-of-four scheduling. This is
not a production account login, network-latency simulation, UI benchmark, or
physical-device performance gate.

The workload generates eight Vaults with twenty real encrypted Credential
Entries each before timing. Each pass starts with an empty isolated SQLite
cache (OS filesystem caches are not dropped). Fixture/schema creation and
initial FFI loading are outside the timer. It exercises production `MemberEntryListService`, `MemberSyncService`,
`MemberSyncRemoteDatasource`, Dio socket transport, `SqliteMemberSyncCache`,
X25519 Vault-key unwrap and MemberIndex decryption through libsodium. The native
SQLite database lives in a unique temporary directory and is closed/deleted;
the application database and secure storage are never read or changed.

Fixture boundaries are explicit:

- A loopback-only HTTP server replaces the backend. It returns one synthetic
  Vault list, one snapshot and one closing empty delta per Vault. There is no
  injected timer, sleep, network delay, real account, TLS or bearer-token flow.
- The fixture Vault-list loader installs encrypted wrappers obtained through
  HTTP, replacing encrypted Vault metadata/list presentation work.
- Fixed independent synthetic session claims replace authentication/token
  storage. Production lease, scope and envelope validation remains active.
- The temporary database schema is a test fixture of policy-2's three tables;
  all cache operations and transactions use the production cache implementation.
- AutoFill candidate rebuild/native provider, Home/Inbox widgets and real
  backend latency are outside this measurement.

The serial baseline uses the same loader, crypto, transport and cache, awaiting
one Vault at a time. The batch mode uses the unchanged production preparation
service. One pair warms up both paths, then five pairs alternate execution order.
Every pass asserts 160 non-corrupt, decrypted synthetic MemberIndex Entries and exactly 17 HTTP requests: one list,
eight snapshots and eight closing deltas. Any added per-Vault context GET,
retry, or per-Entry request fails that invariant. Output contains environment,
timing/count metadata only. Compare medians after excluding `warmup: true`;
there is deliberately no flaky elapsed-time pass threshold.

## Host verification

```sh
PALLADIN_LIBSODIUM_PATH=/path/to/libsodium.dylib flutter test --no-pub test/performance/member_preparation_loopback_test.dart --reporter expanded
flutter analyze --no-pub tool/member-preparation-benchmark/main.dart test/performance/member_preparation_loopback_test.dart
```

The host test substitutes SQLite's FFI adapter for the Android method channel.
It runs one warm-up pair and one measured pair to verify real HTTP/crypto/SQLite
composition and request invariants; those timings are not emulator evidence.

## Authorized isolated emulator run

Use a dedicated emulator and the local debug flavor. Obtain explicit local
build authorization under repository rules. This entrypoint never starts the
application bootstrap, Firebase, analytics, authentication or any cloud client.
The invocation-scoped init script allows the Google Services task to finish
without a configuration file, rather than skipping a task whose outputs other
tasks require. No cloud resources or identifiers are generated. The script
rejects any other target or task. Use the installed Gradle version matching
the repository wrapper:

```sh
# Run from android/. JAVA_HOME must point to JDK 17 (biometric_storage toolchain).
# Set dart-defines to base64("BENCHMARK_REVISION=<exact git HEAD>").
gradle :app:assembleLocalDebug -I ../tool/member-preparation-benchmark/no-firebase.init.gradle \
  -Ptarget=tool/member-preparation-benchmark/main.dart \
  -Ptarget-platform=android-arm64 -Psplit-per-abi=true \
  -Pdart-defines='<base64 revision define>'
```

Install `build/app/outputs/apk/local/debug/app-local-arm64-v8a-debug.apk` on the dedicated
emulator and launch `io.palladin.mobile.local/io.palladin.mobile.MainActivity`. Capture only the
`MEMBER_BENCHMARK_ENV`, `MEMBER_BENCHMARK`, and terminal
`MEMBER_BENCHMARK_DONE`/`MEMBER_BENCHMARK_FAILED` log lines. Preserve the exact
committed revision, APK hash, emulator/API/ABI, runtime/build mode, command and
raw metadata lines with the acceptance record. Final acceptance must rebuild
and rerun after integration from the exact committed tree.

Loopback on an emulator measures actual socket, native SQLite and crypto work
in a debug runtime, but does not reproduce a remote API's RTT or an actual
phone's CPU/storage. A neutral or slower result is valid evidence; do not
replace it with an injected-delay estimate or claim Home/Inbox latency is fixed.

## Persisted metadata reopen

The host regression exercises both 160 and 1,024 Entries. After the existing
warm-repeat passes, it closes the loopback server, locks the production sync
service and calls `unlockAllCached` twice over the same canonical SQLite heads:

- `locked-persisted-index` opens the encrypted grouped metadata index retained
  after lock. Eight Vault-key unwraps are expected, with zero Entry DEK,
  MemberIndex or MemberSecret opens and zero HTTP requests.
- `locked-canonical-baseline` locks again, drops only the auxiliary
  `member_search_index` table in the isolated temporary fixture database and
  reopens the unchanged canonical heads. Every Entry requires one DEK and one
  MemberIndex open; MemberSecret and HTTP counts remain zero. This includes
  rebuilding/persisting the auxiliary index through production code, so it is
  a missing-index recovery baseline, not the exact historical implementation.

Both paths verify the complete Entry count. The subsequent shared-source check
still verifies metadata-only candidates and one selected credential body read.
Reported times are host debug observations, not phone measurements or latency
pass/fail thresholds. The persisted run precedes the missing-index run; neither
OS filesystem caches nor the JIT are reset between them.

For content-preserving empty deltas, the service rebinds only the authenticated
manifest and skips Entry serialization/hashing. Changed Entry deltas still group
and hash the current metadata to identify affected buckets; unchanged ciphertext
is reused. SQLite writes a complete encoded row when the bundle changes.
