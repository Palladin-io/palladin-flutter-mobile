# shell

Navigation shell: bottom nav, FAB ownership stack, settings end-drawer.

- **State:** no BLoC — uses `AppShellScope` (an `InheritedWidget`) so descendants can open the settings drawer and register a FAB.
- **Pages:** `AppShell`, `FabOwnershipStack`, `PlaceholderPage`. **Widgets:** `AppBottomNav` (5 slots + badge counts), `SettingsDrawer`.
- **Layering:** presentation only — no data/domain (it is pure navigation chrome).
- **FAB ownership:** any page that shows a FAB registers it via `FabRegistrar` (pass `fab: null` to suppress a leaked FAB from a covered page). The shell renders the registered FAB in one place.

The scrollable settings drawer groups destinations under Organization and
Account. It derives visibility from the authenticated permission mask: Team and
General remain visible to every member, while Permissions, API Keys and Audit
Logs are omitted when the caller lacks the corresponding read permission.
Billing is an explicit placeholder. Security consolidates password and TOTP;
Data Import links to the existing local import flow. Session actions (lock and
sign out) remain separate from settings destinations. Drawer navigation uses
the centralized `AppRoutes` paths; route guards independently enforce the same
authorization rules.

**Cross-feature deps:** hosts all tab features (vault, agents, notifications).
Settings drawer routes to settings, API keys, and audit. Descendants open the
drawer via `AppShellScope.of(context)` — never mount a duplicate `endDrawer`.

## Brand surfaces

`AppScreen` and the shell use the same `AppBrandBackground` as authentication:
light radial gray with a soft white bloom, and the existing neutral dark glow.
`BrandGrainSurface` adds static grayscale texture behind the dark bottom navigation
and a weaker version behind the settings drawer. Both keep solid base colors;
the texture is decorative, isolated in a repaint boundary, and never covers
labels or changes hit targets. Primary CTA glow is shared by the full-width
and compact primary buttons; disabled/loading actions have no glow.

The light surface uses a brighter neutral ramp (#F8FAFC → #F2F4F7 → #E9EDF2)
with a low-contrast white bloom tapering across its full radius. Legacy wrappers in Vault list/detail, Entry detail,
API key detail, recovery and onboarding delegate to the same background so tab
changes cannot reveal the old gray ramp. Navbar glow originates directly below
the central shield and fades to both sides in dark mode. The light navbar uses
a plain opaque surface and a fine top border, without grain or a central bloom.
Drawer grain is weaker and broader in dark mode. The light drawer uses an
opaque white surface without grain or Material surface tint. The localized version and
Palladin.io share one compact footer line separated by a pipe, without a shield.
The footer is right-aligned; Palladin uses a bold theme-aware wordmark with a
brand-red .io suffix. The settings list has a persistent scrollbar and track
when it overflows, so offscreen actions remain discoverable before scrolling.
The footer stays pinned below the scrollable settings list with minimal bottom
padding inside the device safe area.

Selected Inbox segments reuse `PrimaryButtonGlow`. Navbar icons retain their
active color without a red glow. Detail tabs
in Vault, Entry, API keys and Agent use `BrandTabIndicator` for a glowing red
underline. Inactive and disabled tabs have no glow.

## Directional navbar transitions

Navbar navigation passes a value-only `ShellTabDirection` based on the current
and target icon positions. The four root tab routes use `ShellTabPage`: the
incoming content slides from the tapped side over 260 ms, while the navbar
stays mounted. Settings still opens the existing drawer. Re-selecting the same
tab, direct links, auth redirects and reduced-motion navigation have no slide.
Detail pushes retain their normal platform transitions. The direction travels
only in that navigation's `extra`, with no global tab-history state or timers.
