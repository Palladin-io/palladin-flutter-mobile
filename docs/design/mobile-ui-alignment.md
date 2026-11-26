# Mobile UI alignment — interactive proposal

## Current approved UI contract — 2026-11-25

This section is authoritative. Later dated sections record experiments and
superseded decisions; never implement an old variant from that history.

- Resource lists use simple list A: one neutral surface, full-width dividers,
  40dp identity slot, 14dp name, 12dp secondary text, 16dp row padding. Inbox
  keeps its accepted cards and 44dp footer actions. Status badges align with
  the name in the upper-right of resource rows, never vertically centered
  beside the full identity block.
- Detail content starts 16dp below tabs INSIDE its scroll view. No fixed spacer
  between tabs and the scroll viewport. Horizontal screen gutter is 20dp.
- Related cards and the final detail card above a FAB use the same 16dp gap.
  Use AppFab.scrollClearance for FAB clearance; never append a card margin to
  the last card. Feeds without FAB finish with 16dp, not 96dp.
- Read-only data uses EntryFieldRow.labeled and full-width separators. Identity
  belongs in the header. Edit opens a root full-screen route; one AppActionFooter
  owns Save. Cancel discards drafts; existing permission and mutation gates stay.
- History uses compact 32dp Reveal/Restore controls and an 8dp header inset.
- Team invitation details use labeled rows and paired Resend/Cancel footer
  actions. The edit FAB opens the role editor; Save appears only there.
- AppDetailTabs owns framed, full-width, neutral outlined selection, disabled
  tabs and overflow hints. Never duplicate it per resource.
- CompactDangerZone is the Entry reference: neutral border, inline title and
  trailing delete/action icon. Preserve its compact geometry and optical glyph
  sizing. Copy/reveal/delete use a 44dp touch target with centered glyphs; empty
  fields preserve the same minimum height. Do not restore a large red button.
  WarningZone owns warning styling.
- Member editing contains only role selection; identity metadata stays in Details.
- Authentication uses warm neutral panel grain and the approved soft-b10 white bloom in light mode; dark keeps its subdued graphite recipe. Layers are anchored to the shield center, not screen coordinates.
  BrandHero uses bundled Inter variable weight 800 (PalladinBrand), matching the web
  wordmark weight and -0.01em tracking; copying a 400-weight font family and
  changing fontWeight does not load the correct font asset.
- Compact danger actions use 12dp text and 8dp vertical padding, retaining the
  common 44dp action target.
- TOTP has normal value typography, no leading clock, a small countdown ring
  immediately before Copy, and the same field-row height as neighboring data.
- PrimaryButton and AppFab use primaryAction; counters stay brandRed. Disabled
  Save is neutral. ApproveActionButton is the neutral green-accent approval CTA.
- Settings menu uses the opaque app surface with subtle grain in both themes
  and the shared navigation gradient behind its header. The pinned
  version/wordmark footer has a fine top separator and navigation gradient.
  Back from a settings destination restores its originating menu.
- The bottom shield protrudes above the unchanged navigation height. Canvas
  continues behind it without a horizontal background strip. FAB placement is
  shared with Entries Add; do not tune an individual screen's FAB height.
- Reuse AppRecordList/AppRecordRow, ConfirmationSheet, shared fields/buttons and
  zones before adding a presentation widget. Symmetry means common alignment
  axes, baselines and spacing ownership, not arbitrarily equalizing all heights.

## Preview setup and historical implementation notes


Implementation: `feat/mobile-approved-design` starts at origin/main `fa55af27`.
The accepted prototype remains the visual reference; implementation preserves
newer AutoFill and audit attribution behavior. Not published or merged.

## Architecture

`design/mobile/main.dart` runs the production router, shell, pages and shared
widgets. `AppTheme` is used by both the application and preview. There is no
parallel HTML/React recreation of mobile screens.

Memory adapters supply synthetic Entries, Vaults, agents, grants, audit, sharing,
Team, roles, API keys and account preferences. Lists and mutations share the same
fixture stores. Refresh resets the scenario. Login accepts nonempty demo input;
lock/unlock and logout remain local. Never enter real credentials.

Unhandled API calls are rejected by the preview Dio interceptor. Native AutoFill
is reported unsupported; biometric enrollment is unavailable. Crypto operations
are replaced at the fixture service boundary, not weakened in production. The
sharing page supports an optional `EntryShareCreationCubitFactory` registration;
without it the production constructor remains unchanged. The normal application
entry point never imports `design/mobile`.

Real service logos live in `design/mobile/public` and are copied only into the
preview build. The original PublicAssetImage renders them through same-origin
asset URLs. Fonts/Flutter rendering resources may load from their CDNs; no
Palladin backend, push or analytics is initialized.

## Run

```sh
flutter pub get
./design/mobile/serve.sh 5461
```

Open http://127.0.0.1:5461. The script refuses to start a duplicate listener.
Preview uses a 390×844 phone viewport with matching MediaQuery and safe insets.
The whole phone scales down to fit smaller browser windows; navigation stays
inside the visible phone. iOS presentation is selected for this browser preview. Use the
original Settings drawer to switch theme. Screens use the mobile geometry and
44dp controls, with panel/extension surface, outlined selection, badge and action
patterns shared through production widgets.

## Coverage and checkpoint

Implemented fixtures: Vaults/Entries list, detail, create/edit, archive/history,
sharing create/list/protection/revoke; Agents; Inbox decision controls; audit;
Settings general, Team, roles, API keys, privacy and synthetic security flows.
Device import/export, real image upload, biometrics, OS AutoFill and real account
recovery are not simulated end-to-end; this preview does not certify native
security or device integration.

The previous single-screen component catalog was replaced by this router-based
preview. Next: browser interaction verification, fix any uncovered adapter gaps,
then owner review of the complete light/dark screens before release work.

## Verified in this iteration

- Production routes rendered at 390×844 in both themes: Entries, Vaults, Agents,
  Inbox, organization profile, Team, roles, API keys, security and audit.
- Browser interaction checks: Entry Details → Agents/Logs/History/Sharing/Edit;
  create form; sharing options → ready link; drawer lock → unlock, logout → email
  login → dashboard. No backend was used in these checks.
- Full analyzer passed; focused fixture/navigation/segment/structural-budget
  checks passed (24 checks), four Vault/icon fixture tests, one current-search
  regression, and 26 existing Entry Details tests passed.
- Flutter JavaScript web build passed. Wasm compatibility warnings concern
  existing dependencies; this preview uses the JavaScript build.

Owner visual acceptance and native-device rendering remain pending. This is a
local proposal, not a merged/released mobile redesign.

Full-suite run: 2,257 passed, 21 skipped, 12 failures. One was an obsolete
FilledButton finder after adoption of ApproveActionButton; the focused approval
key-ownership suite passed all four tests after correcting that finder. The other
11 failures are native libsodium loading/SodiumPlatform initialization failures.
The full suite is not green; this local preview is not release approval.

## Phone preview performance and navigation

Grain now reuses one 128×128 raster tile instead of replaying 5,000 points per
tile during transitions. The bounded cache holds decorative pixels only.
A same-browser first Entries transition improved from 2,694 ms to 956 ms with
this change; the final phone-layout run measured 1,089 ms cold and 608/323 ms
on repeat. These are local headless-browser measurements, not native benchmarks.

Entry Details opened from the shell uses its nested Navigator, retaining the
navbar and suppressing the covered list FAB. Outside the shell it retains the
root-navigation behavior. Full-screen authentication/forms remain separate.
Phone geometry, detail/back navigation and the existing detail/tab checks passed
(32 focused tests); a browser check confirmed Home navigation from Entry Details.

## Inbox account identity

Cards keep four property rows, including placeholders for missing values. Access
requests show Entry/Vault, Username, Methods and Reason. The design fixture provides a synthetic account login. Production resolves the
username from the matching unlocked local Member index, with the same session
fences as the Entry label. Transport-supplied usernames are stripped and lock
redaction removes the local value; notification transport/storage never carries it.

## Inbox action hierarchy

Pending-card rejection is a muted text action; approval retains the shared
outlined green ApproveActionButton. Both keep a 44dp touch height and equal
columns. Positive segment counts use brand-red badges with on-brand text;
zero counts are hidden, matching bottom-navigation notification badges.

Inbox card actions now occupy one 44dp row without a tinted footer band or
vertical wrapper padding. Segment selection reaches the full 44dp track height;
the shared track has no inset around the selected border.

Entry Details now uses AppCanvasBackground instead of the authentication
background, the shared AccentButton for Edit, full-height outlined tabs without
the lower divider, and card-border tokens for field separators. This is a
presentation alignment; secret reveal/copy/edit lifecycle is unchanged.

## Zone parity and Inbox separators

Danger zones match web origin/main DangerZone: opaque card fill, full semantic
red border, inline `zone | action` heading, 12dp body gap and shared primary
action. Entry, Vault, Agent and API-key wrappers reuse ActionZone. WarningZone
matches the web amber treatment (6% light / 8% dark fill, 30% border). Inbox
keeps the top footer divider and a full-height divider between actions, with no
distinct footer background or added vertical padding.

## Logs and stable Entry fields

Global and Entry audit feeds reuse AuditLogRow with a continuous bordered list,
semantic left stripe, outlined group icon, existing actor/event wording, neutral
context chips and relative time with an exact-date tooltip. Expanded metadata and
sharing-receipt wording stay available. Event color taxonomy is unchanged.
Core Entry fields remain visible when empty (em dash, no reveal/copy action);
row minimum height matches populated fields. Inbox View/Approve/Deny now share
one borderless text-and-icon renderer, retaining footer separators and 44dp height.

Search geometry now matches Teams with or without a filter action: the leading
search icon reserves the shared control height, preventing no-filter fields
from shrinking. A widget regression verifies equal geometry and 20dp phone
gutters (350dp content within the 390dp preview).

Entry list headers reserve three consistent text rows for both credentials and
API keys; absent metadata/domain uses an em dash. A layout regression compares
API/credential heights. Inbox tests also compare Accept/Deny height and TextStyle
directly against View access; all three use the same renderer.

Mobile audit refinement: plain full-width list rows with a single bottom divider,
no icon tile, card fill or severity rail. Relative time is anchored to the right. Status/context chips use their natural
width and fill the remaining row; only overflow chips expand through +N. Semantic event colors remain in the
status chip, and expanded metadata plus exact-date tooltip are retained.

Card footer audit: Inbox, Sharing and grant review/regrant/revoke use the same
CardFooterAction (44dp, 12dp semibold, 14dp icon, no fill/outline) and
CardActionFooter (top separator only). Sharing retains a vertical separator
between change-protection and revoke. Form submission footers remain separate.

AuditLogList groups events into one opaque, rounded, bordered list surface with
edge-to-edge separators and no individual cards/icons. Global/Vault and Entry logs use
the lazy sliver constructor; Home Recent Activity uses the same list renderer.

Tab press/hover/focus overlays now use AppTheme.tabOverlay with neutral onSurface
alpha (4% hover, 8% press/focus), never the primary red. Material TabBarTheme,
shared segments, agent detail tabs and bottom navigation consume the same rule.

Vault and API-key detail wrappers now reuse AppCanvasBackground, matching Entry
details and AppScreen. Authentication keeps its separate brand background.

Preview builds use content-hashed bootstrap/application script URLs via
`design/mobile/prepare_preview.py` so local rebuilds do not reuse stale scripts.

Approval logs use resource → Agent, with the approver last. Common resource
actions also put the author last. One-line rows open a shared detail sheet
with the complete sentence, exact timestamp and metadata. The offline approval
fixture supplies five chips (event, Entry, Vault, Agent, method) to exercise +N.
Approved/expired Inbox cards open their Entry Details via View Entry.

The offline bootstrap preloads its synthetic Vault directory so Inbox View Entry
works before visiting the library. No production navigation guards are bypassed.

Entry Sharing hides the Details section separator while collapsed; metadata
values align to the trailing edge using GrantDetailRow.valueAlign. Footer
separators remain unchanged. AppFormSection supports showCollapsedDivider.

Compact log copy omits action words already present in status chips: grant
approval is “resource → Agent by actor”; Entry CRUD/access is “resource by actor”,
without the redundant Entry prefix. The detail sheet still names the event.

Status chips across grants, Team, system roles, import, onboarding and plan
labels reuse StatusBadge: neutral fill/border, compact semantic text and optional
icon. Interactive FilterChip/ChoiceChip share AppTheme's matching neutral
selection. Unread counters retain their intentional red emphasis.

Expired grant log copy also omits the status already shown in its chip.
Entry Sharing uses the short Share CTA; Add/Edit 2FA uses AccentButton.

Navigation uses AppHeaderSurface: a separate subtle neutral gradient with a
bottom border. Entry/Vault/API-key detail tabs share AppDetailTabs, filling the
width inside a common frame; long translations scroll. Agent tabs fill their
framed row evenly. Active tabs retain the neutral outline.

Header surface includes the top safe inset, avoiding a textured strip above it.
Inbox uses an edge-to-edge segmented track with its overflow action inside the
same frame; search retains its content gutters. Read-only Entry cards retain 20dp external horizontal gutters and their
internal padding; tabs remain edge-to-edge.

Ordinary list content owns its 12dp top spacing inside the scroll view, so it
scrolls away with search. Inbox tabs attach directly to the header. Canvas grain remains
unchanged; navigation uses its separate subtle gradient surface.

Tab proportions follow extension origin/main src/popup/redesign.css: full-width
track, 6dp internal gutter/gap, 36dp inner tabs, 6dp active-outline radius and
12px medium labels. The track stays separate from the canvas grain. Only horizontal track borders
remain; individual active-tab outlines are intact. The dark header uses a quiet
vertical graphite gradient ending in the tab surface, without a white wash.

Inbox header owns the single separator above the tab track; the track paints
only its bottom line. Its overflow action has no vertical separator.

Header content uses equal 12dp vertical padding (system safe insets remain
separate). Search uses 12dp top/bottom scrolling spacing. Dark bottom navigation
previews the same navigationGradient as the header, mirrored vertically, without
its old grain overlay; light navigation remains unchanged.

Dark bottom navigation adds a restrained neutral radial glow centered under the
Home shield, fading into the shared navigation gradient.

Entries (global and per-Vault) and Agents preview compact rows in AppRecordList,
a shared lazy surface with full-width separators. Entry reveal/share/navigation
actions remain; Agent lifecycle metadata moves inside its row. Inbox is unchanged.
The navigation shield glow is wider and lighter (radius 3.4, white alpha .035).

Latest preview: header/tab boundaries now have one separator owner (tabbed AppBar surfaces omit their bottom border; Agent tabs omit the top border). Agent Logs reuse the shared audit feed, chips and detail sheet with a fixed agent filter. Focused audit/tab checks: 18 passed.

Current preview iteration: Entries have 12dp vertical row padding; compact Agent lifecycle metadata has its own spacing and stronger 11sp text. Entry History shares AppRecordList with full-width separators, neutral reveal actions and relative dates with exact-date tooltips. Share and read-only Edit use the common AppFab with share/edit icons; form Save remains explicit. Bottom navigation reserves the shield headroom, so it cannot overlap fixed actions. History/detail/list tests passed; all 39 Sharing tests and both navigation geometry cases (0/34dp safe inset) passed.

## Geometry audit — 2026-11-23

Scope: current mobile preview and its shared production widgets. Values below are
Flutter logical pixels at default text scale; this is a focused geometry audit,
not a claim that every route/state has received device acceptance.

Confirmed inconsistencies:
- Entries: 12 vertical / 14 horizontal row padding; Agent compact rows: 8 / 14;
  Audit rows: 14 on all sides. Agent metadata adds its own 6 gap and 2 vertical
  padding, so apparent row density does not follow a single rule.
- Record titles: Entries 13 semibold, Agents/Team 14 semibold; metadata uses
  10/11/12 depending on surface. Header title is 16 bold.
- Entry/Vault/API detail tabs use AppDetailTabs (36 inner tab, 50 track,
  12 medium text). Agent detail still owns a custom track with content-driven
  height, 10 vertical padding and 12 semibold/bold text. Inbox uses
  AppSegmentedControl, a third implementation.
- Main search/primary/accent/footer actions are 44 high, but compact buttons
  combine 10 text, content-driven or explicit 32 height and varying tap target
  settings. Different roles can have different visual sizes, but each role
  needs one consistent specification and an accessible touch target.
- Header→content is owned in different places: AppScreen.appBar adds 16 by
  default, list scroll contents start at 12, tab hosts add 12 themselves.
  This split ownership previously caused doubled gaps and separators.
- Icon→text gap is 10 for Entries, 8 for Agents. Both list avatars are 40;
  Inbox uses 36. Inbox is intentionally a separate card pattern, but its title
  and content axes still need to align consistently.
- FAB placement differs: shell FAB has shell Insets on top of Scaffold
  positioning, detail FAB uses right20/bottom16. Their baseline is visibly
  different even though both controls are 44.
- CardActionFooter is 44 without outer fill; AppActionFooter adds 12 above
  and below a 44 action (68 before safe area). This is a deliberate role
  distinction but must not be used interchangeably.
- Radii are 6 on active tabs, 8 compact controls, 10 standard controls,
  12 cards/FABs. The values can form a valid hierarchy; custom agent tab hover
  still uses radius4 and default Material buttons remain a drift risk.

Fixed in this iteration: bottom navigation used a rectangular InkWell press/
hover overlay. It now uses a bounded circular InkResponse with radius28;
navigation layout and reserved shield headroom remain unchanged.

Proposed alternatives (not applied):
A. Minimal normalization: preserve current density; align titles at14,
   record padding12v/14h, icon gap8, first-content gap12; share tab geometry
   and FAB placement. Lowest visual change, still relatively dense metadata.
B. Balanced mobile rhythm (recommended): screen gutter20; shared card inset16,
   record padding12v; gap8 within groups,12 between controls,16 between sections;
   record title14, supporting text12, metadata/chips11; controls44 with consistent
   touch areas; tab track50/inner36, no header→tab gap; first content12.
   Entry/Agent/Team lists share row anatomy. Inbox keeps its card layout.
   Two-line vs three-line content may have different heights; equivalent rows
   must align and grow naturally for text scaling rather than clip.
C. Spacious mobile: gutter20, inset16, row padding16v, section gap20,
   controls48, title15/support13. Easier reading but fewer visible records and
   greater departure from the accepted compact web/extension direction.

Recommended implementation order after owner choice:
1. Shared spacing/type/size roles, then common header/tab/FAB ownership.
2. Entries/Agents/Team record anatomy; keep Inbox structure.
3. History/Logs metadata and remaining forms/footers using the same roles.
4. Compare dark/light at 360/390/430 logical widths, long PL labels and enlarged
   system text. Check touch targets, scrolling, safe area and keyboard.

### Interactive A/B/C comparison
Owner requested side-by-side visual experiments before selecting a density.
Run `python3 design/mobile/build_variants.py` with Flutter available. The script
builds isolated disposable copies of the existing preview and shared widgets;
it does not change the product sources or replace the default preview. Each
recipe is explicit and fails if a source anchor changes. Builds are sequential,
with logs under `build/mobile-variants/`. Results are copied into the existing
local server directory at `/variants/a/`, `/variants/b/`, `/variants/c/`.
Open `http://127.0.0.1:5461/compare.html`: Entries/Agents/Logs/Inbox/Home and
light/dark controls load the same surface in all three 390×844 frames; each
frame supports the existing local navigation and fixtures. These are density
experiments, not a completed migration of every form or an approved new default.
The comparison page belongs in the preview host, not in the shipped mobile app.

### Accepted baseline A and preview focus repair — 2026-11-23
Owner selected minimal correction (A). Applied its record title14, row padding12,
icon/text gap8, header/content gap12 and neutral Agent tab typography to the main
preview widgets. B/C remain comparison experiments only.

The offline Flutter PreviewBinding now keeps its synthetic app lifecycle resumed:
switching browser focus between iframes/outside the phone no longer dispatches
inactive/resumed events that clear Entry Details and trigger another reveal loader.
This binding is imported only by design/mobile/main.dart; product app lifecycle,
background plaintext cleanup and lock behavior are unchanged. A failing-then-passing
binding test verifies repeated inactive/hidden/paused/resumed signals do not reach
the fixture observers. Forty focused binding, Entry and audit layout tests passed;
analyzer clean. Main preview and all three comparison variants rebuilt. Browser verification: opening Entry edit, moving focus outside the iframe and returning preserves the edit form without resetting it.

### Agent list and detail cleanup — 2026-11-23

List rows show identity, type and status only; lifecycle dates and attribution
remain in Details. Agent approval/reactivation now reuse the neutral ActionZone
surface, inline save uses PrimaryButton, and detail padding follows the accepted
14dp baseline with 16dp between sections.

### Entry list alternatives — 2026-11-23

Four unselected experiments at `entries-compare.html`: A identity-first two-line
list, B metadata with actions below, C separate cards with a metadata/action row,
D compact domain-first rows with inline expansion. All reuse the actual Entry
icon, username, reveal and navigation components with synthetic fixtures.
`design/mobile/build_entry_variants.py` patches only a disposable source copy;
no default production layout changes. A single build selects the experiment by
preview-only `layout` query parameter. The host supports light/dark and individual
links, showing four columns or two on a laptop.

### Selected Entry list D — 2026-11-23

Owner selected the most compact Entry list. The shared compact EntryListCard now
shows name and domain (Vault/dash fallback), 40dp icon and 8dp vertical padding.
The trailing chevron toggles the existing reveal panel; the row opens Details.
Applies to global and per-Vault lists. Selection-only rows retain selection
behavior, and unavailable/corrupt records retain their explanatory metadata.

### Compact Vault list — 2026-11-23

Vault library now composes AppRecordList with shared VaultCard compact rows:
40dp icon, name and Entry count, 8dp vertical padding, full-width separators and
row navigation. Removed the dated footer; the Vault chooser reuses the same
identity row in its standalone surface. Entry A versus D is awaiting owner
clarification; D remains the default until selected otherwise.

### Shared simple list A selected — 2026-11-23

Owner reconsidered D and selected A as the starting point across resource lists.
Entries, Agents and Vaults now share 40dp icons, 16dp vertical row padding,
14dp titles, a secondary identity line and trailing navigation chevrons inside
AppRecordList. Entries show username (Vault/context for non-credentials);
inline reveal is removed from compact rows. Inbox retains its approved cards.
This supersedes the earlier D baseline and pending A/D decision above.

### Read-only Entry fields match the extension — 2026-11-23

Reference: extension origin/main `EntryFields.tsx` and `redesign.css` detail-field
pattern. Mobile reuses EntryFieldRow.labeled: label over value, sans-serif value,
no leading field glyph, vertically centered copy/reveal actions, 16dp horizontal
and 12dp vertical padding. One opaque bordered card owns full-width separators.
Script/TOTP fields keep their specialized behavior within the same padded rows.
Secret masking, lifecycle clearing and copy handlers are unchanged.

### Sharing, grants, History and overflowing tabs — 2026-11-24

Sharing places the outlined status above the recipient at the leading edge,
leaving the full card width for the recipient. Grant metadata values align at
the trailing edge through GrantDetailRow. History keeps actor/status/date
above its expanded snapshot and reuses the labeled EntryFieldRow presentation.
AppDetailTabs switches to horizontal scrolling when the longest label cannot
fit its equal-width slot; edge chevrons fade into the track and disappear
when that scroll edge is reached.

### Sharing layout refinement and populated examples — 2026-11-24

Sharing status uses a leading icon/text band with a separator, not a chip.
Metadata uses equal flexible columns and 12dp type, including the compact
Details disclosure. History omits the Current chip; GitHub has three synthetic
versions and a public demo TOTP configuration. Empty 2FA shows only Add 2FA.
Entry Delete is outlined red; navigation paints its reserved shield headroom
so pinned Save meets the navigation surface without a transparent strip.

Navigation correction: preserve the original 58dp bar and separator position.
Only fill the 14dp shield headroom with the footer surface; do not extend the
bar or move its gradient/border upward.

Sharing header correction: recipient | semantic status on one row, no status
icon or separate band. Expanded Details omits its redundant closing notice
and divider. Entry danger card returns to the filled primary Delete action
with a neutral outline and smaller 12dp heading.

Final refinement: Sharing status is intrinsic-width at the trailing edge,
separated from the expanded recipient. History shows actor/time without event
chips. Entry danger card uses the ordinary card border and a light trash action.
Navigation has one continuous background gradient across shield headroom while
the separator remains at its original 14dp offset; item geometry is unchanged.

Navigation visual correction: the 14dp shield headroom is transparent on
content screens. Navigation fill begins at the separator, not above it;
painting the reserved headroom produced the unwanted horizontal strip.

Entry danger action is now only a trailing trash IconButton in the title row,
with localized tooltip and unchanged delete confirmation. ActionZone supports
an optional trailing action and omits body spacing when no body is supplied.

### Full-screen Entry editing — 2026-11-24

Edit now pushes the existing form on the root Navigator, above bottom navigation,
matching Add Entry. Save/cancel return to Details; tests cover repeated saves,
conflicts, draft preservation and sign-in method edits through this route.
Read-only Sign-in methods omit Add, TOTP is visible with Copy, and field action
icons use 18dp. Sharing status has no separator. Navigation retains its original
58dp bar with transparent shield headroom now that editing has its own screen.

### Navigation seam and compact Entry actions

The shell extends the page viewport through the 14dp shield headroom to the
navbar separator. Scrolling content is clipped at that separator, not above the
shield. Each route retains its opaque canvas so slide transitions cannot expose
the previous page through the incoming page. Navbar height and icon positions
stay unchanged; its fill begins below the separator.
Read-only sign-in methods render saved provider icons with account tooltips;
absent methods omit the row. Entry Danger Zone uses 16dp horizontal / 12dp vertical
padding and a 22dp trash glyph (optically matching 18dp copy icons) in the same 26dp action
slot as field actions.

Entry Details reuses EntryListIcon at 28dp beside its header title.

Home search carries Entry icon references through both Recent and typed results,
reuses EntryListIcon, and shows type plus Vault name in the secondary line.
PreviewSearch implements selection without analytics so result taps reach the
production navigation handlers instead of failing on the fixture stub.

### Detail readability refinement

Audit rows retain 12dp vertical padding and 8dp between sentence and metadata; the proposed larger spacing was rejected.
Agent Details initially renders shared read-only field rows, with its status
on the right and an Edit FAB opening a full-screen form with a pinned Save footer. Entry, Agent and Vault destructive
actions reuse CompactDangerZone with a neutral border and a trailing icon;
existing permission gates and confirmation callbacks are unchanged.

The Agent Edit FAB opens the existing form above shell navigation; Save is pinned
and successful saves return to Details. The header reuses AgentAvatar. Read-only
TOTP uses EntryFieldRow typography and geometry with Copy only, without a timer
glyph or countdown. API-key danger actions also reuse CompactDangerZone. Audit
row density is unchanged; resource/agent emphasis is semibold while author and
connecting words are muted to improve reading hierarchy.

Agent identity and status appear only in the header. The metadata card has
edge-to-edge separators and field-owned padding, matching Entry Details.
Detail FABs align with Entries Add using AppFab.overlayBottom; Agent Details
keeps a full-height scroll viewport with AppFab.scrollClearance bottom padding.
At the scroll limit, the last card ends 16dp above the FAB, matching the gap
between data and Danger Zone. Never clip content above a reserved FAB lane.

Read-only TOTP retains the standard field typography and height. Its 24dp countdown ring shows remaining seconds before Copy; Copy stays aligned with other field actions. Detail content starts with the same 16dp section gap used between its cards.
