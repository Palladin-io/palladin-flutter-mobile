# Firebase client configuration

Per-flavor Firebase client files are explicit, ignored build inputs:

| Platform | Ignored destination |
|---|---|
| Android | `android/app/src/{local,staging,production}/google-services.json` |
| iOS | `ios/config/{local,staging,production}/GoogleService-Info.plist` |

A fresh clone contains no Firebase project selection. Native builds require the
matching client file; the platform build fails if it is missing. Unit tests and
static analysis require no Firebase account or client file.

Download the client file from your Firebase project, then install it explicitly:

```sh
python3 tool/configure_firebase.py --flavor local --platform android \
  --source /path/to/google-services.json
python3 tool/configure_firebase.py --flavor local --platform ios \
  --source /path/to/GoogleService-Info.plist
```

The installer rejects a file for a different distribution package/bundle before
writing. It preserves the complete original bytes, including existing OAuth
metadata and other Android clients. It does not create, delete or reconfigure
OAuth clients, consent-screen publishing status or redirect URIs.

## What these files contain

`google-services.json` and `GoogleService-Info.plist` identify a Firebase
project and registered client application. Their API keys, project IDs, app
IDs, and sender IDs are embedded in every distributed app and are therefore
public client identifiers. They are not service-account credentials and do not
grant administrative access to Firebase or GCP.

Keeping client configuration outside Git does not mean that an unrestricted Firebase
project is safe. The project must remain protected by controls enforced outside
the app:

1. **Application restrictions** bind Android keys to the expected package name
   and signing-certificate fingerprints, and iOS keys to the expected bundle
   ID.
2. **API restrictions** permit only the Google/Firebase APIs required by the
   mobile client. Never add unrelated services such as the Cloud SQL Admin API
   or the Generative Language API to a Firebase client key; create a separate,
   narrowly restricted key if a non-Firebase client API is introduced.
3. **Firebase Security Rules** default-deny every enabled data product and grant
   only the minimum access required by its data model. Palladin currently uses
   Firebase Cloud Messaging rather than Firestore, Realtime Database, or Cloud
   Storage; if a data product is enabled later, its rules must be reviewed and
   deployed before client code is merged.
4. **Firebase App Check** is enforced for every enabled product that supports
   it, using platform attestation appropriate to production Android and iOS
   builds. Debug providers and tokens must stay limited to development
   environments.
5. **Server credentials** stay outside this repository. Service-account keys,
   FCM server credentials, APNs signing keys, and signing material belong in a
   protected secret store with least-privilege access and rotation.

App Check, Security Rules, and API/application restrictions solve different
problems. None is a substitute for the others, and none makes a Firebase client
API key confidential. App Check coverage is product-specific; it must not be
described as protecting an unsupported API.

## Current Firebase scope

The mobile client uses Firebase Cloud Messaging for push delivery. Application
authentication is JWT-based through the Palladin REST API; the app does not use
Firebase Authentication. No Firestore or Realtime Database dependency is
present.

Push payloads must contain only routing identifiers and non-sensitive display
metadata. Credentials, decrypted vault content, master keys, vault keys,
recovery material, and auth tokens must never be included in a notification.

## Repository and CI behavior

The native build reads the ignored files at the paths above. The owner-dispatched
store workflow installs `FIREBASE_ANDROID_CONFIG` (raw JSON) and
`FIREBASE_IOS_CONFIG` (raw plist) from GitHub variables in the protected
`mobile-store-<flavor>` environment. Selection follows **distribution flavor**,
not backend environment: production-flavor tests against the staging API keep
the existing production Firebase project. Never replace that configuration with
a new project merely because the API is called staging.

PR CI receives no cloud configuration, signing material or cloud access. It
checks the installer with synthetic files, including preservation of OAuth and
rejection of mismatched distributions. Public Firebase identifiers remain in
older Git commits; removing runnable defaults does not revoke them. Review
provider-side restrictions independently.

## Maintainer checklist

When adding or rotating a Firebase app:

1. register the exact package name or bundle ID for the flavor;
2. restrict the client key by application and API;
3. verify Security Rules for every enabled Firebase data product;
4. configure and enforce App Check where supported;
5. download the client file into ignored local configuration or the protected
   distribution environment variable;
6. confirm that no service-account or signing credential entered the diff;
7. run a flavor build and validate push token registration against the intended
   backend environment.

When one Firebase project contains several Android apps, the downloaded
`google-services.json` can contain every registered Android client. The Google
Services Gradle plugin selects the entry matching the active flavor's final
application ID. Do not trim the file to the production client because that
silently breaks the `local` and `staging` flavors.

## Explicit Google OAuth build inputs

Direct Google Sign-In is independent of Firebase Cloud Messaging. Application
code and Runner Info.plist have no Palladin-owned OAuth defaults. Set
`GOOGLE_SERVER_CLIENT_ID` to the web OAuth client accepted by the selected
backend, and on iOS set `GOOGLE_IOS_CLIENT_ID` to the client for the distribution
bundle ID. These are public identifiers, not client secrets.

After setting these variables in your local environment, run:

```sh
python3 tool/configure_google_oauth.py --flavor local --platform ios
flutter run --flavor local -t lib/main_local.dart \
  --dart-define-from-file=config/google-oauth-local.local.json
```

Use `--platform android` on Android. The helper creates ignored Dart build
inputs and, for iOS, an ignored flavor-specific xcconfig with the client ID,
server client ID and reversed callback scheme. Re-run it when changing the
backend or distribution identity. Missing or malformed inputs fail before
writing; missing Dart configuration rejects Google login before invoking the
native SDK instead of falling back to a Firebase-embedded client. Password
login is unaffected.

The owner-dispatched store workflow reads `STAGING_GOOGLE_SERVER_CLIENT_ID`
and `PRODUCTION_GOOGLE_SERVER_CLIENT_ID` from GitHub variables, selecting by
**backend environment**, without falling back from missing production to
staging. `GOOGLE_IOS_CLIENT_ID` belongs to the protected
`mobile-store-<flavor>` environment and selects the **distribution identity**.
Production-distribution/staging-backend store tests therefore keep their iOS
identity while using the staging token audience. Configure these variables
before dispatching a store build; PR CI uses synthetic inputs and no cloud access.

Existing deployments retain their current OAuth client, redirect URIs and Firebase
project. New isolated Firebase projects are a separate migration, not a
prerequisite for making a fresh clone independent of Palladin infrastructure.
Provider restrictions and native login/push smoke tests remain operational
release gates. Public client identifiers in earlier commits alone do not
require a history rewrite.

## Explicit API destination

The default entry point uses local configuration. Staging and production read
`PALLADIN_API_BASE_URL` from a Dart build define, with no Palladin-host fallback.
The value must be an absolute HTTPS URL without user information, query or
fragment; a self-hosted base path is supported. See the README for ignored JSON
inputs and local run commands.

Both store distribution environments must define `STAGING_API_BASE_URL` and
`PRODUCTION_API_BASE_URL`. Android and iOS select the URL using the same backend
environment as the Google server audience. Production-distribution tests against
staging keep their production Firebase, OAuth iOS identity and signing inputs.
No provider configuration is changed by selecting the API destination.
