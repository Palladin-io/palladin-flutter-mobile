# Firebase client configuration

The per-flavor Firebase client configuration files are committed intentionally:

| Platform | Path |
|---|---|
| Android | `android/app/src/{local,staging,production}/google-services.json` |
| iOS | `ios/config/{local,staging,production}/GoogleService-Info.plist` |

## What these files contain

`google-services.json` and `GoogleService-Info.plist` identify a Firebase
project and registered client application. Their API keys, project IDs, app
IDs, and sender IDs are embedded in every distributed app and are therefore
public client identifiers. They are not service-account credentials and do not
grant administrative access to Firebase or GCP.

Committing client configuration does not mean that an unrestricted Firebase
project is safe. The project must remain protected by controls enforced outside
the app:

1. **Application restrictions** bind Android keys to the expected package name
   and signing-certificate fingerprints, and iOS keys to the expected bundle
   ID.
2. **API restrictions** permit only the Google/Firebase APIs required by the
   mobile client.
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

The client files are tracked and read in place by each platform build. Public
pull-request CI does not inject Firebase secrets and does not need access to a
private parent repository:

- Android reads `android/app/src/<flavor>/google-services.json`.
- iOS selects `ios/config/<flavor>/GoogleService-Info.plist` through the flavor
  build configuration and copy script.
- The committed configuration is verified by
  `test/config/firebase_client_config_test.dart`, which checks only public
  project, package, bundle, and Firebase App identifiers and never snapshots an
  API key.
- Store signing material is supplied only to the manually triggered store-build
  workflow and is never available to fork pull requests.

## Maintainer checklist

When adding or rotating a Firebase app:

1. register the exact package name or bundle ID for the flavor;
2. restrict the client key by application and API;
3. verify Security Rules for every enabled Firebase data product;
4. configure and enforce App Check where supported;
5. download and commit only the client configuration file;
6. confirm that no service-account or signing credential entered the diff;
7. run a flavor build and validate push token registration against the intended
   backend environment.

When one Firebase project contains several Android apps, the downloaded
`google-services.json` can contain every registered Android client. The Google
Services Gradle plugin selects the entry matching the active flavor's final
application ID. Do not trim the file to the production client because that
silently breaks the `local` and `staging` flavors.
