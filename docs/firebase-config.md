# Firebase configuration files — intentionally committed (CVT-216 / M13)

These per-flavor Firebase config files are **committed on purpose**:

| Platform | Path |
|----------|------|
| Android  | `android/app/src/{local,staging,production}/google-services.json` |
| iOS      | `ios/config/{local,staging,production}/GoogleService-Info.plist` |

## Why committing them is safe

`google-services.json` and `GoogleService-Info.plist` contain the Firebase
**client** configuration — project id, app id, sender id, and a client API key.
None of these are secrets: they are extracted verbatim from any distributed app
binary, so treating them as confidential provides no security value. Google's
own guidance is that these files are safe to commit.

The security control that actually protects the project is **API key
restriction in the GCP console**, which must be kept in place:

- **Application restriction** — each key is locked to our app: Android package
  name + SHA-1/SHA-256 signing certificate, iOS bundle id.
- **API restriction** — each key is limited to only the Firebase APIs we use
  (Firebase Cloud Messaging / Installations). No other Google APIs are callable
  with the key even if it leaks.

Because we use **no Firebase Auth and no Firestore** (JWT auth is via our own
REST backend; push is FCM-only — see the root `CLAUDE.md`), the blast radius of
the client key is limited to sending device-registration/installations traffic
for our own restricted app.

## `.gitignore` / CI story

These files are **tracked, not ignored** — deliberately. The build reads them
in-place per flavor (`android/app/src/{flavor}/`, iOS via the flavor xcconfig),
so there is no CI-injection step and none is required. If a prior policy note
elsewhere claimed these are CI-injected, that note is stale: the source of truth
is that they are committed and restricted.

## Known gap (tracked, non-blocking)

The Android client API key is currently **reused across all three flavors**
(`local`, `staging`, `production`). This is acceptable *only* because the keys
are application-restricted in GCP, but it weakens environment isolation. The
preferred end state is a distinct Firebase app (and therefore distinct config /
key) per flavor. This is a GCP-side change, out of scope for this repo.
