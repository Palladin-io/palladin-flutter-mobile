# Account privacy

The optional first-entry sheet is deferred while `/share` is visible, including
after explicit account continuation. Covering that one-shot receiver would retire
its RAM copy. Leaving sharing resumes the normal offer; no consent is granted,
denied or marked as offered by this deferral. The mounted runtime regression
first reproduced the unwanted sheet after authentication became ready.

`ConsentCubit` owns the current Identity response, temporary form suspension,
request idempotency and the runtime freshness deadline. `PrivacyRuntime` binds it
to AuthBloc, locale, app foreground/background and generic route templates.

- `PrivacyRuntime` offers the native sheet over the ready application on first
  eligible entry, after registration, setup, verification and unlock. An unknown
  purpose must have a current notice; an unavailable catalogue never interrupts
  entry and may be offered after a later successful read. Dismissal grants nothing.
  The legacy `/privacy-choices` URL resumes the normal auth guards.
- The Account drawer opens the settings sheet over the current screen without
  navigation. Direct `/settings/privacy` links use `PrivacySettingsPage` with
  Security behind the sheet and replace the route with `/settings/security` on close.
  Both surfaces reuse `ConsentChoices`; analytics and marketing are independent.
- Data comes from authenticated `/api/account/consents`. Writes send the displayed
  client notice version/locale, expected revision, random request ID and exact
  source (`mobile_onboarding` or `mobile_settings`). The server owns all domain
  validation; clients deserialize the version-matched contract.
Account analytics consent automatically applies on every signed-in web/mobile
installation after a fresh authenticated response for the accepted notice version.
No device activation, browser preference, localStorage entry or mobile cache file
is required. Old activation records are ignored. Changing language does not revoke
an accepted version. A different current notice version still requires explicit Save.
Unknown, denied and withdrawn choices never authorize capture.

A form holds a memory-only suspension while editing a withdrawal or saving a batch.
Polling cannot override that suspension. Successful completion releases it;
closing/cancelling the form discards its draft and resumes the saved account choice
within the normal freshness/lifecycle rules. Closing Privacy never revokes a grant.
Failed writes remain visible with an explicit retry; no reconnect queues a decision.
Account replacement and logout invalidate in-flight reads/writes.


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

Consent text is bundled with the client independently of the receipt API.
Failed receipt reads keep controls unavailable and permit continuing. No marketing
sender was introduced. Final PL/EN notices, privacy text, retention, App Privacy
and Data Safety declarations remain a coordinated release gate. ATT is a separate
assessment, not a blanket analytics permission prompt.


## Account consent decision — 2026-09-19

This decision supersedes all historical references below to per-installation
activation, local on/off status and dismissal disabling capture. The UI has only
the account switches, expandable notice details and Save choice / Accept all.
Capture still requires the independently configured analytics release flag and
project key. Removing device activation does not publish or enable that configuration.
The API receipt contract, archived notice texts, event scope and transport stay unchanged.

## Historical presentation decisions

The dated sections below retain the previous design record. Their per-device
activation behavior is superseded by the account-consent decision above.

## Explicit startup choice and settings (CVT-609, 2026-09-13)

The startup presentation is a modal over the ready authenticated application,
after setup, verification and unlock. Web uses ModalShell; mobile uses a
root-native bottom sheet. An unknown account
choice can be offered once per running session; dismissing is only a UI state,
not a stored denial or permission. The user can continue without optional consent.

Essential is informational and always active, without a switch. Product analytics
and email news/offers start off when unknown. Switches edit a draft, then equal
outlined Save choice / brand-primary Accept all actions commit decisions.
Save preserves the switches; Accept all explicitly grants both purposes. Full current notices
remain expandable before deciding; short explanatory labels do not replace the
versioned full notice. The backend registry contains version metadata only.

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
authentication and processing release configuration are unchanged.

Consent footers reuse `SheetActionButtons(equalActions: true)`; other sheets keep
their existing confirm/cancel styling. The startup sheet disables drag/backdrop
dismissal and prevents closing while a request is pending. Close before saving
suspends local capture, then returns to the current application screen.

## Dialog-only startup and settings (owner decision, 2026-09-13)

Both entry points call showPrivacyConsentSheet: one native root bottom sheet,
SheetSurface header, scrollable ConsentChoices and pinned primary/secondary footer.
There is no inline consent panel. The drawer closes itself and opens the sheet
without pushing a page, preserving the current route, edited fields and Back stack.
Direct privacy links open once over Security and replace the route with Security
after Close, system Back or successful Save. Startup completion pops only the
sheet; it does not mutate authentication or routing. `ConsentCubit` keeps a
memory-only offered-account set shared by the runtime and explicit sheets, so
opening from the drawer also prevents a later duplicate automatic prompt.

A navigator-scoped presentation guard prevents duplicate consent sheets. Runtime
recognizes an explicit /settings/privacy visit before deciding on a first-entry
prompt, so it neither stacks nor offers a new prompt after leaving that route.
This session UI state never authorizes analytics. Source, rather than callback
presence, selects the settings device state/activation affordance.

Save is outlined secondary; unknown optional choices stay off and untouched Save records both
explicit denials. Unchanged Save can close without a write when the displayed version is already recorded.
An explicit Save of a new displayed version records the choices against that version.
Successful Save/Accept all closes the sheet. Failed/partial saves retain retry.
Close/Back cannot dismiss during the entire form write, including refresh and the
interval between the two purpose writes; the form owns an additional PopScope.
Dismissal stops local activation without modifying account consent. Existing
freshness, per-installation activation, keys and release-off
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
Ordinary Save also confirms analytics grants last; withdrawals still run first. No backend,
canonical notices, marketing pipeline, telemetry scope or release gates changed.


## Email marketing copy and detail ownership

The category is Email marketing / Marketing e-mailowy. Its one-line description identifies Palladin news/offers by email; the expanded
three-sentence notice explains that essential transactional, account and security
messages do not depend on marketing consent. This does not implement a
marketing sender. Full PL/EN details come from the client catalogue, with an immutable version
and a matching archive in `docs/consent-notices/`. Identity stores the decision receipt. Controller identity/contact remain in
the linked legal documents. The original draft.3 wording is retained exactly in the first client-owned version.

## Consent detail separators

Only the consent notice ExpansionTiles receive a local copy of the inherited
theme with a transparent divider and borderless expanded/collapsed shapes.
Explicit shapes also override any inherited ExpansionTile borders when the
shared form is reused. Card outlines, the pinned action-footer divider, spacing
and the native ExpansionTile focus/keyboard behavior remain intact.

Consent cards use `AppColors.cardFooterOverlay`, matching the pinned action
footer. The detail trigger follows the description without an extra spacer and
retains a 44px row. Expanded client-owned notice text is left-aligned, 12px with
1.5 line height; the client does not replace or rewrite the notice body.


## Review corrections: local opt-out, recovery and conflicts

The account grant is now sufficient after a fresh read (owner decision 2026-09-19).
Temporary form pauses are scoped to the current session and released on completion
or dismissal; no disk activation generation or persistent account block remains.

A successful authoritative read clears a recovered load error independently of
an unresolved write failure. Save failure is tracked separately from the retryable
request: definite non-409 rejections (including 400/403) retain the visible save
error and selected draft through successful reads and failed-read recovery. The
form remains open and permits correcting, explicitly saving again with the current
revision/new request ID, or dismissing. Only 409 resets the draft. A load retry
refreshes authority first; the identical-write retry appears only for a retained
unconfirmed batch. HTTP 409 discards the rejected decision and the form's remaining stale
batch/draft, refreshes authoritative choices, and shows a localized instruction
to review and save again. A failed conflict refresh keeps that instruction pending
until reads recover. Reconfirmation uses the displayed revision and a new request
ID. Other definite HTTP 4xx rejections also discard the stale batch; identical
retries are reserved for transient/ambiguous failures (including 408/429/5xx).

Both ordinary Save and Accept all confirm analytics grants after marketing and
keep local capture off through partial failure and the pending retry. Confirmed
account decisions remain visible; only the unconfirmed remainder is retried.

Verification links carrying a token bypass optional privacy and account-setup
redirects so the real verification page consumes the token. After successful
verification, Continue checks the refreshed session claim and required default-vault
provisioning, dispatches `AuthEmailVerified`, and navigates to token-less
`/verify-email`. This resumes the existing guards, including setup/unlock before home. The token remains intact until
that check succeeds, including when the session was already email-verified.
Regression coverage lives in privacy cubit/widget tests and
`test/core/router/privacy_verification_router_test.dart`; router regressions click
the real Continue button with the production router, verification cubit and AuthBloc.


## Delayed runtime prompt and navigation preservation

For both new and existing accounts, `PrivacyRuntime` presents the shared root-native sheet over
the mounted destination, including safe first entry. A slow initial read or later
successful poll never redirects away from the destination. Save and dismissal pop only
the sheet, retaining the current route, query, form state and previous Back stack.
The runtime rechecks authentication, foreground state, route and consent after the
frame before presenting; token verification pages are left uninterrupted. Route
checks use the delegate's top state, including imperative pushes, so visiting
Privacy settings consumes the once-per-session offer there as well.

`privacy_runtime_test.dart` exercises slow reads and actual 30-second polling with
an edited stateful input, both Save and Close, and Back to the original route.
400/403 widget regressions retain choices/error across repeated authoritative
reads, recover failed reads, and reconfirm without replaying rejected request IDs.


## Visible route analytics and bounded sheet layout (mobile R3)

Pageviews use `routerDelegate.state.fullPath`, the visible top match's route
**template**, for both declarative navigation and imperative `context.push()`.
The underlying `currentConfiguration.fullPath` is not the pushed destination.
Empty configurations and missing/empty templates emit nothing; resolved paths,
parameter values, query strings and fragments are never used as fallbacks.
Template-based deduplication suppresses consent refreshes and same-template pushes,
while Back emits the newly visible template. Runtime tests inspect encoded capture
payloads through an in-memory adapter, with and without a shell navigator.
The optional runtime analytics dependency defaults to the production singleton.

`SheetSurface` requires a bounded host height and expands its body below the
header. `ConsentChoices` fills that body and assigns all space above its footer
to the scroll viewport. Expanding details changes only scroll content, never the
footer position. `SheetActionButtons` still owns the keyboard and bottom safe-area
insets exactly once. Essential's informational label can wrap in the category row
at large text scales. Equal footer actions retain their 44px minimum and share
the natural height of the longest scaled label, preventing glyph clipping.
Borderless notice tiles and the two equal actions remain.
Numeric layout regressions cover startup/settings at 390×1200 and 320×568, Polish
text at 1×/2×, both details throughout expansion, bottom scrolling and keyboard
insets at both scales, using Flutter SDK Roboto metrics instead of synthetic
Ahem glyphs. The debug-only native preview exports read-only render geometry alongside
its existing release-off and empty-key state for screenshot verification.

## Entry timing correction (owner decision, 2026-09-15)

The separate pre-verification privacy route, auth flag and auth events have been
removed. The runtime requires an onboarded, verified, unlocked account and leaves
login, registration, setup, verification, unlock and recovery routes uninterrupted,
including their outgoing navigation frame. Unknown purposes without current notices
do not trigger a sheet. The once-per-session offer is consumed only by presentation
or an explicit visit to Privacy settings. Existing consent write, activation,
idempotent retry, capture release gates and native sheet controls remain intact.


## Client-owned notices and version receipts (2026-09-18)

The client displays its own PL/EN notice and submits the exact displayed
`noticeVersion`, locale, purpose and choice. Version `2026-09-18T00:00:00Z`
identifies the first client-owned release and its UTC effective-from instant.
Identity returns receipt state without `currentNotice`; the data adapter attaches
the local notice. A legacy response's text cannot override the bundled wording.

`docs/consent-notices/2026-09-18.json` archives the exact four texts and pins the
linked policies. Tests compare every localized notice with this archive. Never
edit published text under the same version: add a new archive and matching
backend metadata entry before releasing a new client notice.

The server records authenticated user, purpose/scope, choice, displayed version,
locale, source and its own UTC timestamp. It rejects unknown or future versions
and never infers the displayed version from the acceptance time. An older
installed client may still submit a known effective older version. Existing
revision fencing, retries, history and withdrawals remain unchanged.

An explicit Save records an updated displayed version even if its switch value
has not changed. Enable on this device reconfirms analytics without reconfirming
an unchanged marketing choice. Reading a receipt or updating the client version
never constitutes consent. Receipt storage does not enable analytics release
flags or add a marketing sender.
