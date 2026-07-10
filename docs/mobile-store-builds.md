# Mobile Store Builds

The `Mobile Store Builds` GitHub Actions workflow creates store-ready artifacts:

- Android: signed `.aab`
- iOS: signed `.ipa`

Run it manually from GitHub Actions and choose:

- `flavor`: `staging` or `production`
- `platform`: `both`, `android`, or `ios`
- `build_name`: semantic app version, for example `1.0.0`
- `build_number`: store build number; if empty, GitHub run number is used

## Android Secrets

Required GitHub repository secrets:

- `ANDROID_UPLOAD_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Create the base64 value from the upload keystore:

```bash
base64 -i upload-keystore.jks | pbcopy
```

The upload key must be the key registered for the app in Google Play Console.

## iOS Secrets

Required GitHub repository secrets:

- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `IOS_TEAM_ID`
- `IOS_PROVISIONING_PROFILE_STAGING_BASE64`
- `IOS_PROVISIONING_PROFILE_PRODUCTION_BASE64`

Create the base64 values:

```bash
base64 -i distribution_certificate.p12 | pbcopy
base64 -i Palladin_Staging_AppStore.mobileprovision | pbcopy
base64 -i Palladin_Production_AppStore.mobileprovision | pbcopy
```

Provisioning profiles must be App Store distribution profiles for these bundle IDs:

- staging: `io.palladin.mobile.staging`
- production: `io.palladin.mobile`
