# Account privacy

`ConsentCubit` owns the current Identity response, local installation activation,
request idempotency and the runtime freshness deadline. `PrivacyRuntime` binds it
to AuthBloc, locale, app foreground/background and generic route templates.

- `PrivacyOnboardingPage` is the separate optional step after password registration
  or an OAuth response with `isNewUser: true`. Continuing does not require either
  consent and does not grant it. Existing sessions do not silently opt in.
- `PrivacySettingsPage` lives at `/settings/privacy` in the Account drawer group.
  Both surfaces reuse `ConsentChoices`; analytics and marketing are independent.
- Data comes from authenticated `/api/account/consents`. Writes send the displayed
  server notice version/locale, expected revision, random request ID and exact
  source (`mobile_onboarding` or `mobile_settings`). The server owns all domain
  validation; clients deserialize the version-matched contract.
- A file in the application cache retains only the notice version and `activationRevision` for
  that account. They contain no key material, tokens or analytics session. Account
  consent alone does not activate a new installation. A later withdrawal/regrant
  changes the epoch and makes earlier local activations unusable. Application cache
  is excluded from normal mobile backups; restoring ordinary preferences cannot
  enable a new installation. Cache eviction also disables analytics until explicit
  reactivation. No consent activation is stored in SharedPreferences. See
  [Apple file-system guidance](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html).
- Withdrawal stops the in-memory transport before storage/API work, including on
  failure. Failed decisions remain retryable with the same request ID. Responses
  from an older account/session never authorize analytics. Storage failure still
  permits sending a server withdrawal; a failed activation write keeps collection
  off.

The client reads consent on authentication, locale change and foreground resume,
and polls every 30 seconds while foregrounded. Polling also discovers network
recovery within that interval. A read failure stops collection immediately. Each
confirmed snapshot expires after server `maxAgeSeconds` (default 60, maximum 300);
no event extends this deadline. Backgrounding cancels work and clears memory
session IDs. A resume needs a new response. No offline queue is retained.

`AnalyticsService` uses a separate, five-second Dio capture transport with no API
authentication interceptors, cookies, profile updates or redirect following. It
sends only reviewed `mb:` interactions and generic route templates. Caller
properties are dropped; URLs, route parameter values, Vault contents, email,
tokens and device metadata are not payload fields. It creates a random session
ID only in memory after permission is current. Native PostHog dependencies were
removed, including the iOS Pod lock and macOS generated plugin registration, so
there is no native SDK startup, autocapture, replay, flags or error collection.
API headers contain only a fixed `x-platform: mobile` product tag.

Build configuration requires `POSTHOG_PROJECT_KEY` plus
`CLIENT_ANALYTICS_RELEASED=true`; all source defaults keep release disabled and
keys empty. The capture host is the EU endpoint. Use separate staging/production
projects, including production-identity store builds targeting staging.

The Identity notice catalogue is intentionally unavailable until final legal
review. The controls show this state and still permit continuing. No marketing
sender was introduced. Final PL/EN notices, privacy text, retention, App Privacy
and Data Safety declarations remain a coordinated release gate. ATT is a separate
assessment, not a blanket analytics permission prompt.
