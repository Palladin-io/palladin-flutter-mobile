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


## Explicit startup choice and settings (CVT-609, 2026-09-13)

The startup presentation is a modal, not the settings page. Web reuses ModalShell
with focus trapping over the safe pre-verification/key-setup surface; eligible
first entry can offer it over the authenticated shell. Mobile uses a root-native
bottom sheet before the existing setup/verification guards. An unknown account
choice can be offered once per running session; dismissing is only a UI state,
not a stored denial or permission. The user can continue without optional consent.

Essential is informational and always active, without a switch. Product analytics
and email news/offers start off when unknown. Switches edit a draft, then equal
outlined Save choice / brand-primary Accept all actions commit decisions.
Save preserves the switches; Accept all explicitly grants both purposes. Full current notices
remain expandable before deciding; short explanatory labels do not replace the
backend notice version/text or activate the empty release catalogue.

The two existing endpoints are not atomic. Save processes the decisions in order,
reports no overall success on partial failure and retains only unconfirmed decisions
for an identical idempotent retry. Turning analytics off suspends local capture
before Save. Errors and dismissal fail closed. Saving an unrelated marketing change
never activates a previously inactive installation. Settings shows a simple local
on/off status and an explicit Enable on this device action; only the initial
analytics grant, Accept all, or that activation action enables the current installation.

The debug preview uses real widgets/components and the normal consent data path
against a local synthetic API. It is visibly labelled TEST FIXTURE. It cannot run
as a released preview and never configures an analytics key. Production entrypoints,
active notices, authentication and release configuration are unchanged.

Consent footers reuse `SheetActionButtons(equalActions: true)`; other sheets keep
their existing confirm/cancel styling. The startup sheet disables drag/backdrop
dismissal and prevents closing while a request is pending. Close before saving
suspends local capture, then completes the optional routing step.

## Dialog-only startup and settings (owner decision, 2026-09-13)

Both entry points call showPrivacyConsentSheet: one native root bottom sheet,
SheetSurface header, scrollable ConsentChoices and pinned primary/secondary footer.
There is no inline consent panel. PrivacySettingsPage auto-opens once, then retains
only its AppScreen navigation and Manage choices launcher. Close or system Back
returns to that launcher; the next Back follows normal navigation. The startup
completion still dispatches PrivacyChoicesCompleted through the existing guards.

A navigator-scoped presentation guard prevents duplicate consent sheets. Runtime
recognizes an explicit /settings/privacy visit before deciding on a first-entry
prompt, so it neither stacks nor offers a new prompt after leaving that route.
This session UI state never authorizes analytics. Source, rather than callback
presence, selects the settings device state/activation affordance.

Save is outlined secondary; unknown optional choices stay off and untouched Save records both
explicit denials. Valid unchanged Save can close with no fabricated API write.
Successful Save/Accept all closes the sheet. Failed/partial saves retain retry.
Close/Back cannot dismiss during the entire form write, including refresh and the
interval between the two purpose writes; the form owns an additional PopScope.
Dismissal stops local activation without modifying account consent. Existing
freshness, per-installation activation, empty active notices, keys and release-off
configuration remain unchanged. Full current notices stay available in details.

## Two-action footer (final owner decision, 2026-09-13)

Startup and settings have exactly two footer actions: Save choice (outlined) and
Accept all (brand red), with equal width/height. Unknown optional choices still
start off; untouched Save records two explicit denials when notices are available.
There is no Essential only footer action. Close/Escape/Back never create consent.

Accept all requires both current notices and forces two affirmative decisions,
even for existing account grants. It first stops local analytics, confirms marketing,
then confirms analytics through the existing installation activation mechanism.
Thus a partial failure leaves capture off and the dialog open; retry uses only the
unconfirmed remainder with the original request IDs. Successful retry activates
this installation only after both decisions are confirmed. The endpoints remain
non-atomic; a confirmed account decision is not rolled back or hidden on failure.
Ordinary Save retains existing draft/withdrawal/per-device behavior. No backend,
canonical notices, marketing pipeline, telemetry scope or release gates changed.
