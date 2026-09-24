# App Center

**2026.09 (Beta)** · Copyright © 2026 FluffNet LLC · MIT License.
The Cargo package uses the equivalent SemVer `2026.9.0-beta`; `VERSION` holds
the user-facing release name shown by About.

A native Flatpak software center for Fluff Linux, built with Rust (standard
library only), QML, and the system Qt 6 and libflatpak libraries. There are no
background update services, notifications, or tray components. Settings currently
contains Flatpak source management.

## Home and catalog exclusions

Home shows **Recommended Apps** above **All Apps**, sharing the main page's
scrollbar. Compact name-and-icon tiles keep All Apps visible below them, including
at the minimum window size. The curated list is Brave, Discord, Google Chrome,
Minecraft Launcher, Sober, Spotify, Steam, Telegram and Visual Studio Code, always
alphabetical. Only apps available from
the configured official stable Flathub catalog are shown; recommendations never
add a source or install an app.

Publisher/developer names use the same accent-colored styling as app details
throughout recommendations, catalog/category/search cards, Installed, Updates and
Queue. They come from existing AppStream metadata; unavailable names are hidden,
never replaced with the repository name or an invented publisher. Updates can
resolve the matching app/source/branch from local catalog or installed metadata
without network requests. Names are plain text, not HTML or a verification badge.
Publisher text adapts down by at most two pixels (never below 10 pixels) and can
wrap onto two lines. Recommended tiles give publishers their full width, so the
curated publishers remain readable without hovering even at the minimum window
size, while keeping All Apps visible. Exceptionally long metadata retains a
readable font and uses a full-name tooltip as the final overflow fallback.

The sorting control is available on **Home and every catalog category**, with
A–Z/Z–A, most/least popular, and newest/oldest published release. Home defaults to
most popular. Each category starts at A–Z; its temporary choice resets when switching
categories and is never written to the config. Returning from app details resumes
the current category visit. Recommendations, search relevance and Installed sorting
are independent. Unknown values go last in both
directions; real zero install counts remain valid. Both popularity orders omit
apps currently shown in Recommended Apps, including when popularity is offline.
Name/date sorts, categories and search still include those apps. Catalog cards
show the app name and description without category tags; category filtering stays
available in the sidebar. Installed keeps its independent size sorting.
The selected Home order is saved immediately as `Catalog/homeSort` in
`~/.config/flufflinux-appcenter.conf` and restored on the next launch. Missing or
invalid values (including the removed `size-asc`/`size-desc` choices) default to
`popularity-desc`. Other valid keys are `popularity-asc`, `name-asc`, `name-desc`,
`release-asc` and `release-desc`.
Window settings and unrelated config entries are preserved. The steady-state
popularity explanation is omitted; loading/offline status remains available.

Popularity uses Flathub's public `installs_last_month` count (last 30 days), loaded
when Home or a category is shown with a popularity sort and cached for 24 hours. No installed-app
list is sent. Failed requests retain saved statistics; without saved data, the
page explicitly falls back to A–Z. Download sizes and release dates come from
local Flatpak/AppStream metadata, not per-app network queries. Download sizes
exclude shared runtimes. None of these actions checks for app updates.

Edit **`/etc/flufflinux-appcenter/exclusions.conf`**, one exact Flatpak/AppStream ID
per line. Blank lines and `#` comments are supported; wildcards are not. The
defaults hide `org.videolan.VLC` and `org.libreoffice.LibreOffice`, since Fluff
Linux supplies them as system packages. **An installed Flatpak copy is never
hidden**: it remains visible/manageable and can receive updates. Otherwise the
exclusion removes it from Home, categories, search and recommendations. This is
a catalog presentation rule, not a security policy blocking direct file installs.
Restart App Center after editing the file, or use Settings' Refresh. App Center
re-evaluates the installed exception after its install/removal transactions.
An empty config disables exclusions; a missing/unreadable config uses the bundled
defaults. Installed system packages are not mistaken for installed Flatpak copies.

`make install` preserves an existing config. `DESTDIR=... make install` automatically
copies the host's edited exclusions into fakeroot; if absent, it installs the
bundled defaults. Use `EXCLUSIONS_FILE=data/exclusions.conf` for defaults-only,
reproducible staging, or point it at a curated file. Uninstall preserves the config.

Catalog tests: `sh tests/run_catalog.sh`, `sh tests/run_qml_suite.sh`,
`python3 tests/integration/test_catalog_exclusions.py` (read-only populated-catalog
check), and `python3 tests/integration/test_exclusions_packaging.py` (temporary
staging only). `tests/integration/HomeSmoke.qml` checks the native layout and live
public popularity data without checking for updates or changing installed apps.

## Manual updates

**Updates**, directly below Installed, shows an installed-style list in the main
window, keeping the sidebar and header visible. Search is grayed out and disabled
while Updates is selected.
Opening/reopening the page, starting App Center, refreshing Installed, and
finishing transactions do **not** check for updates. Only **Check for Updates**
starts the check. Loading, cancellation, timeout, and partial source errors are
visible; checking never enters Queue or deploys an app/runtime transaction.

User and system apps appear together; new installs continue to prefer the user
installation, while updates target each app's existing installation. Matching
user/system repositories with identical signing and source policy appear as one
source in Settings. During an explicit check, a missing system `flathub` (or
`flathub-beta`) source used by installed apps/components is restored from the
official repository definition only when the matching, enabled, verified user
source exists. Flatpak handles system authorization; adding the source may ask
for an administrator password. Existing, disabled, differently named, or
third-party sources are never overwritten or automatically enabled.

Missing, disabled and unreachable origins are listed as skipped, not selectable
updates. A partial check does not claim every app is up to date. Source changes
invalidate prior update candidates and require another explicit check.

Apps and runtimes are listed A–Z (apps first), selected by default. Each row
shows the installed and available version, source/branch, and maximum download
estimate including required components. The selected total counts shared
components once. Actual transfers can be smaller because of cached data,
language subsets and deltas. Missing published version labels use an explicit
commit revision instead of inventing a version. Version labels come from
Flatpak/AppStream; the selected update is checked against its reviewed commit.

Changed sandbox permissions have a **View Permission Changes** dialog showing
added and removed rules in the existing grouped layout. Unknown permission
metadata is explicitly unavailable, never “unchanged.” These are changes to
the app's declared permissions; existing overrides and portal grants are not
modified by the comparison.

**Update Selected** queues only the selected deployments. Required runtimes may
update with their apps even if their standalone row is unchecked. The worker
verifies the installation, full ref, current commit, source identity/signing
configuration, and resolved operation plan before deployment; stale plans fail
with a recheck request. It cannot silently add a source, remove an app, or update
another unselected app. Updates request the latest signed release through
Flatpak's existing system helper, then compare every resolved commit with the
reviewed plan before authorization or deployment. They do not use arbitrary
commit selection, which Flatpak restricts to root for system installations.
No additional root service or relaxed authorization policy is needed.

Successful app deployment records its UTC last-update time in
`$XDG_DATA_HOME/FluffNet LLC/flufflinux-appcenter/update-dates.json` (normally
under `~/.local/share`). Records are keyed by installation and full ref, survive
restarts/Queue clearing, and appear in Installed and at the bottom of app
details in the system's locale/timezone. Original install dates remain separate.
No-op, failed and cancelled-before-deployment updates do not acquire a new date;
a completed deployment is recorded even if a later operation fails. Previously
unobserved/external updates say **Not recorded** rather than guessing a date.

Repeatable offline tests build two versions of two tiny apps plus a shared
runtime. `--keep` preserves old/new commits, bundles and a manifest; `--reset`
restores only that fixture's isolated installation, not the normal user's apps:

```sh
sh tests/run_updates.sh
sh tests/run_qml_suite.sh
python3 tests/integration/test_updates.py --keep /path/to/new-fixture-directory
python3 tests/integration/test_updates.py --reset /path/to/new-fixture-directory
```

The September 23 VM fixture is retained at
`/home/mai/appcenter-update-fixtures/20260923`, reset to v1 and ready to retest.
The regular app installation is not used by these mutation tests.

App details includes **View App Permissions**, a read-only, scrollable dialog
with grouped icons, explanations and a centered Close button. It fills the app
window with a 32px outer margin, resizes with it, and keeps Close visible while
the permission list scrolls using the same edge scrollbar as the main app list.
The heading is `App Permissions - App name`, with the app name bold and no
introductory subtitle. Groups fill two equal-width, independently stacked
columns, so a long section cannot create a gap in its neighbour. Narrow windows
fall back to one column in the original order. Network, audio,
devices, display, shared memory, files, persistent storage, session/system bus,
extra capabilities and USB portal rules are kept in a consistent order; entries
within each group are sorted. File access modes and explicit denials remain
visible, and unknown/future permission values are preserved. Environment values
are not permissions and are never displayed.

Installed apps use `flatpak info --show-permissions` for their exact installation,
architecture and branch, including Flatpak overrides. Uninstalled apps use the
selected source's exact URL/name/ref: cached metadata first, with a read-only
metadata fetch when necessary. Local `.flatpak` bundles can provide their own
metadata. Loading, unavailable data, retry and a 30-second timeout are explicit;
closing a dialog cancels only its own request. This work never enters Queue or
installs apps/adds sources. Dynamic access granted through portals is separate
from these sandbox permissions.

## Appearance

The page, header and sidebar share the KDE window color. Cards, fields and
dialogs share one subtly raised, opaque surface derived from it, without
independent blue-gray tints. Custom panels and controls use an 8-unit corner
radius; normal borders are 1 unit and keyboard-focus outlines are 2. Header
and sidebar separators meet once instead of stacking rectangle outlines, and
align to physical pixels at fractional scaling. All text inherits the desktop's
general font (Noto Sans on Fluff Linux), using the same scalable Qt rendering
as typed text. Small count/metadata labels must not opt into native hinted
bitmaps: those produce visibly different glyphs, including 7, at fractional
scaling even with identical font family and size. The configured
desktop font family and size are retained; individual headings keep their sizing.
Navigation, categories, action buttons and preview controls use the same hover
color, with a visible background tint and explicit hover support even after touch
input. Hover does not add focus outlines. Shared buttons render
their own text/icons so KDE's background-drawn labels remain visible.
Category backgrounds explicitly cover their full hit area, overriding KDE's
native list-item insets so the edges have the same hover tint as the center.
Installed rows use a stronger neutral border for the nested removal button so
it remains visible over the row's hover tint. App-view Back has an outer inset
that keeps its whole hover background away from the window edge.
Clicking/tapping empty page or header space clears the previously focused
control. Buttons accept keyboard focus via Tab, but mouse/touch presses clear
any previous keyboard focus without leaving a focus outline. Passive pointer
handlers preserve clicks, scroll drags and photo gestures. Text inputs still
accept pointer focus; dropdowns keep temporary focus for arrow/Enter selection
and clear pointer focus on dismissal. Modal Cancel defaults retain their focus.
Closing the application menu with a mouse/touch action clears its opener's stale
focus; keyboard dismissal with Escape keeps focus for continued navigation.
The application/source menu buttons toggle closed when pressed again. Outside
press dismissal excludes the opener so releasing it cannot reopen the menu.
The source arrow is a centered, font-independent chevron. The read-only native
`tests/integration/PointerFocusSmoke.qml` checks that interaction and captures
the arrow and app page without starting any Flatpak operations.

Installed and every category fit the sidebar's available logical height without
scrolling. Spacing, row heights, text and icons adapt as the window shrinks or
desktop scaling increases. Labels can shrink further to fit the available width.
This lays out actual font/icon sizes rather than scaling a rendered text texture.
The App Center icon/title is left-aligned in its header with a 16px outer inset.

App Center defaults to maximized. It creates and updates
`~/.config/flufflinux-appcenter.conf` automatically, recording `width`, `height`
and `maximized` in a `[Window]` section. Width/height are the normal, restored
window's logical-pixel size, not the maximized size. Resizing and switching
between maximized/windowed update the saved preference while the app runs;
minimizing is not a startup preference. On launch, a size larger than the
screen's available area opens maximized instead. Invalid/missing values use
safe defaults, and unrelated config keys are preserved. Custom test QML does
not read or change the user's window settings.

Catalog and Installed scrollbars sit at the outer right edge for the full page
content height, with a persistent contrasting thumb and a minimum 44-pixel
drag target. Catalog cards share the available width and spare viewport height,
keeping consistent gaps without leaving a large empty band below the rows.
Scrolling retains its normal continuous movement and edge clipping: partially
visible cards are not hidden, and there is no row snapping.
Scrollbar thumbs remain directly draggable by touch as well as the mouse;
KDE's transient-touch setting cannot turn off their interaction.

`tests/integration/StyleSmoke.qml` is a read-only visual check in the real KDE
session. It captures the catalog, Installed, app and Queue pages plus native
and Qt-rendered count comparisons in `target/style-*.png`, then leaves the
catalog open. It does not start transactions or change the desktop theme, font
or scale. The QML styling tests also cover dark, light and custom palettes.

`tests/integration/DownloadsSortSmoke.qml` verifies sorting with real installed
byte counts and captures Installed, empty results, and wide/narrow Queue.
Download progress is simulated; its completed card uses already-installed Steam.
It also checks app-title navigation/back and clearing finished history while
preserving an active fixture. The check never starts transactions, launches apps,
or changes desktop settings.
It requires Steam to be installed and 0 A.D. to be present in the catalog.

`tests/integration/AppMetadataSmoke.qml` is another read-only VM check: it
opens five real catalog apps, verifies their version/developer labels and
successfully loaded artwork, exercises the missing-icon fallback and recovery,
and captures `target/metadata-*.png`. It also checks installed Size/Version
for Discord and AAT, and leaves AAT's page open.

## Install and remove apps

- App pages show Size and Version in a compact stack beneath the developer, read from the
  same local catalog (no additional network request). Unknown versions are
  omitted; dependency totals appear below when needed. Large action buttons sit
  to the right, with the same 26-pixel outer inset as the app icon on the left
  and at least 176 × 56 logical-pixel touch
  targets. On narrow windows the buttons move below the information, while
  progress keeps its full width. The
  developer's name is displayed without a “By” prefix.
- The Size/Version stack stays visible after installation, using the deployed
  app's disk size and installed version, not the catalog's available version or
  download estimate. Exact local Flatpak bytes use MiB/GiB throughout Installed
  and app details. Dependency totals remain hidden for installed apps, and
  unknown installed versions are omitted. No network lookup is needed.
- App actions match the Queue button's rounded neutral background, subtle
  border and icon-and-label layout. Install shares its arrow shape, in green;
  Open keeps the play icon and Uninstall the red trash icon. Hover, disabled and
  keyboard-focus states remain visible, without a solid accent fill.
- Catalog artwork uses Flatpak's stable `active` deployment path, not the
  disposable snapshot directory. A catalog refresh can no longer leave an
  already-open page pointing at deleted icons. Missing artwork falls back to
  the themed application icon on app pages, catalog cards, Installed and Queue.
- Install from an app's information page. New apps, dependencies and software
  sources are installed **for the current user**, without administrator prompts.
  App Center's system-wide default-handler registration is separate from where
  Flatpaks are installed. The catalog's source and branch are preserved.
- The three-dot menu beside Search lists **Settings** first, then **About**. Settings
  opens to **Flatpak Sources**, with Add Source, enable/disable, remove, details,
  and refresh controls. There are no priority controls. Identical user/system
  sources appear as one row, based on repository URL, signing keys and policy
  configuration rather than display name. User-only sources remain unprivileged;
  system or merged-source removal invokes Polkit action `com.flufflinux.appcenter`.
  The checkbox controls the user copy. Source details retain the installation scope.
  Source checkboxes have centered 24px indicators inside 44px touch targets,
  contrasting unchecked borders, neutral hover tint and keyboard-focus outlines.
  The information icon opens Source details with a top-right Close button. Opening
  it focuses the information, not Close; Tab still reaches Close and Escape dismisses
  the dialog. Closing it also clears the opener's focus. The information button
  uses the same Kirigami renderer and logical icon size as About in the menu, so
  fractional scaling does not select the unrelated large blue icon variant.
  Add Source's Cancel includes its glyph. Settings shows a spinner with queued,
  checking or confirmation status throughout source-file/URL preparation,
  including network waits and eventual errors; that work stays out of Queue.
  User-source names omit the redundant `(User)` suffix in Settings, Installed
  and app details; system-only names retain `(System)`. Installed metadata uses
  the same scalable text rendering as the rest of the interface.
  Choose File uses the desktop file chooser, preferring KDE's XDG portal path
  without changing the platform theme. An explicit
  `PLASMA_INTEGRATION_USE_PORTAL=0` override is respected.
- Removing a merged source covers both copies. A dedicated root-owned helper
  can only remove explicitly validated system repositories; it cannot execute
  arbitrary commands, install apps or change trust policy. Administrator
  authentication is required each time and cancelling authentication leaves both
  copies intact. Sources can be removed while apps/runtimes from them remain
  installed, using Flatpak's supported `remote-delete --force` operation. Source
  removal never uninstalls apps or deletes their data, but updates from that source
  stop until it is restored. The user copy is removed only
  after system removal succeeds; partial failures remain visible.
- With no configured repositories, the Add Source dialog offers **Add Default
  Sources** at its bottom-left to restore signed official Flathub explicitly,
  including after the user previously removed it.
- On first run with no repositories, the official signed Flathub repository is
  added automatically. Existing system repositories are copied into the user
  installation with their public signing keys, verification policy, filters and
  other settings intact. Same-name/different-address conflicts get a separate
  deterministic user name, never overwrite an existing source. Disabled sources
  remain disabled, and deliberately removed copies are remembered in
  `~/.config/flufflinux-appcenter.conf` rather than recreated on every launch.
- Official Flathub stable/beta URLs are automatically trusted; names alone are
  never trusted. Other newly supplied repositories still require confirmation.
  Source changes run outside the GUI thread and never install apps themselves.
- Apps offered by more than one source have a dropdown beside Install. Choosing
  a source changes the app's metadata, version, size estimate and installation
  request together. The catalog keeps one card per app. App details and Installed
  show the source; installed entries report their actual installed origin.
- App pages show **App size** and **Total size with dependencies** before
  installation (only **App size** when their displayed size text matches, even
  if the underlying byte counts differ slightly). These
  are download estimates from Flatpak's existing local
  repository metadata, not installed disk usage. App estimates, dependency sizes
  and live transfer amounts all use the same binary MiB/GiB formatter: an app
  estimated at `1.77 GiB` also reads `1.77 GiB`
  in the progress total, never `1.90 GB` for the identical byte count.
  Dependencies already available in the user or system installation are excluded.
  Opening an app reads this metadata directly before showing the page: no network transaction, waiting
  state, extra size cache, or saved size results. Automatic runtime/locale/driver
  extensions are included; build SDKs and optional debug extensions are not.
  Installed app pages also register their current estimates, so uninstalling
  refreshes the correct app's sizes before the Install action reappears, without
  needing to leave and reopen the page.
- **Install starts immediately**, without an installation-confirmation dialog.
  New third-party software sources require an explicit trust confirmation; source
  additions can remain after cancelling the later app installation. Missing
  local metadata shows unavailable sizes, never a fake zero. Installation still
  resolves the current plan normally, so actual transfers can differ from the
  repository's published estimates.
- Queue (formerly Downloads) keeps this session's app installations, overall progress, and
  errors, with each app's icon beside its name (and a themed fallback when
  artwork is unavailable). Cancelled jobs disappear immediately from both Queue and the app page.
  Source additions and file/source preparation never appear, including failures;
  their errors use the source/input dialog instead. Opening a local Flatpak only
  prepares its information page; its actual installation appears in Queue.
  Cancellation signals Flatpak and closes the worker's input; a 250 ms watchdog
  stops that dedicated worker if it fails to exit. Late progress cannot revive
  the cancelled job, and a retry waits for its worker to exit before starting.
  Cancelling the only job also hides the Queue
  button; other completed/failed jobs stay. Install/download work and removal
  have separate workers, so an app can be removed while another downloads.
  Each worker processes its own queue serially; Flatpak retains its normal
  installation/repository locking around shared changes. Cancellation and
  progress are isolated per worker, and confirmations have unique tokens.
  A single overall progress bar includes every planned component, with
  a plain percentage above its right edge (no component-completion count). Progress text
  uses the normal foreground color: white in the dark theme, dark in the light
  theme. On the same row above the bar, left-aligned
  `128.00 MiB / 512.00 MiB (2.30 MiB/s)` shows the total received bytes and live speed.
  Each amount switches independently from MiB to GiB at 1,024 MiB, so
  larger transfers read `181.90 MiB / 1.77 GiB (2.11 MiB/s)`.
  Speed uses a two-second rolling sample of actual network bytes, resets between
  pulls, and drops to zero during stalls; it never advances the progress bar.
  The byte/speed line disappears after all downloads finish, while the single
  overall bar continues through installation.
  The overall estimate weights transfer work at 90% and confirmed deployment at
  10%, never moves backwards, and reaches 100% only on transaction success.
  Flatpak does not expose a deployment percentage: no timer invents progress
  while it deploys a component. The unfinished section shows activity during
  deployment, including local bundles without fine-grained import callbacks;
  their file bytes are never counted as network downloads. Online dependencies
  of a bundle still appear in the download total.
  Received bytes are summed across the whole transaction. The initial total is
  Flatpak's maximum download estimate; each completed pull replaces its estimate
  with actual transferred bytes (locale subsets/reused content can reduce it).
  During online installs the app-page sizes use this same transaction accounting,
  so a reduced language-pack transfer updates the page total and progress total
  together; the page never retains the old maximum while the bar shows less.
  Local bundles keep their separate file/import sizes, not a network-byte substitute.
  Queue uses the same compact progress display, without dependency/component
  rows or introductory text. Completed apps offer Open directly from Queue,
  using their current installed record; there is no completion text. The action
  disappears if the app is removed or another operation starts for it.
  Clicking an app's icon or title opens its information page; Back returns to
  the same Queue page. Progress updates preserve each card and its pressed
  state, so updates between press/release cannot interrupt title/icon or Cancel
  clicks. Clear History at the top right uses KDE's clear-history icon and hides finished entries
  only, preserving active/pending work, stable cancellation IDs and installation
  dates. The Queue title stays centered between the header controls.
  Errors, cancellation and confirmation messages remain visible.
  Queued installs show only “Pending…” in the status area of both views, with
  no progress bar, percentage or transfer figures until their worker starts.
  Pending installs can still be cancelled.
  Successful installs leave Open/Uninstall actions, not completion text,
  on the app page; their completed Queue history remains available.
- Removals never appear in Queue or its badge. Their progress/errors are
  shown in the Installed row and app view only; successful removal leaves no
  lingering completion text on the app page. Before Yes, both views show only
  “Waiting for confirmation”, without a progress bar. Confirmation is offered
  immediately, even while a worker is busy. After Yes, a queued removal shows
  “Pending…” without a progress bar. Once its worker starts, it shows
  “Uninstalling…” with activity but no Cancel button, including while finished
  sub-steps are being cleaned up. “Complete” never appears on the app page.
  Successful removal updates the installed record before completing the job,
  and discards older in-flight list results, so Open/Uninstall cannot flash back
  before Install appears.
  It also hides that deployment's finished Queue entries, leaving other
  apps/scopes/branches and active work alone. Failed or declined removal keeps
  the existing history.
- Installed lists user and system applications, with version and installed size.
  Its sorting menu offers name A–Z/Z–A, installation date newest/oldest, and size
  largest/smallest. Sizes sort by exact deployed bytes, not rounded display text;
  unknown sizes/dates sort last in either direction. Filtering keeps the selected
  order, and empty catalog/Installed results say “No results.” Real loading errors
  remain visible.
  Open an app, view its information, or uninstall it from its row or app page.
  App details omit the technical installation/scope/branch/architecture row.
  The website is a plain clickable link, aligned with the other detail values
  without a button box or padding. Hover/keyboard focus underlines the URL;
  long addresses stay bounded by the value column.
- Uninstall asks **“Uninstall [app]?”**, with a short paragraph explaining app/data
  removal and compact **Yes / No** buttons. System-wide removals explain their
  all-users scope in the paragraph instead of the heading.
  Yes force-stops all of that app's running sandboxes for the current user,
  verifies they have exited, and deletes **the current user's sandbox directory**
  at `~/.var/app/APP_ID`, then resets that app's portal permissions. This deletion
  is irreversible. Other users' data, documents saved elsewhere, and shared
  runtimes are not deleted. If cleanup fails, the job reports an error instead
  of claiming a fresh uninstall. No or Escape leaves the app and its data alone.
  Unrelated apps are never stopped.
- After each transaction, App Center rebuilds the current user's exported icon
  cache, then Plasma's application database, then broadcasts KDE's icon-reload
  notification. This also clears cached missing icons in the running launcher,
  not just App Center. It does not restart Plasma, change the selected icon theme,
  or rewrite root-owned icon directories. Installed metadata is then refreshed.
- Run the app as your **regular desktop user**, never root. Existing system apps
  remain visible. Uninstalling one explicitly warns that it affects all users
  and may require normal desktop authorization; new installations never do.
- Closing while work is active asks you to wait or cancel. Cancellation does not
  roll back dependency operations that already completed.

## Local files and browser links

Open files with **App Center** from the file manager, or let your browser open
Flatpak links through the registered desktop handler. Drag-and-drop and command
line inputs also work; there is no separate file/link picker in the catalog.
Supported inputs:

- Local `.flatpak` bundles, `.flatpakref` references and `.flatpakrepo` sources.
- HTTPS references, including `flatpak+https://…` browser links.
- `flatpak:org.example.App` and `flatpak://org.example.App` IDs.

Files and links open the app page with sizes and an Install button; merely
opening a file/link does not install the app. Local bundles and new third-party sources
retain their trust warning. Remote references are
limited to 2 MiB, with a bounded timeout and HTTPS-only redirects. Insecure HTTP
and URLs with embedded credentials are rejected. Signed Flatpak repositories
and bundle verification use libflatpak; private sources requiring additional
web/token login are not yet implemented.

The desktop entry accepts URLs with `%U`. A per-user socket forwards new files
and links to the existing App Center window, keeping one session's queue.

## Supported platform and dependencies

Fluff Linux (Arch-based), KDE Plasma 6, Wayland. No macOS or Windows builds.

```sh
sudo pacman -S --needed base-devel pkgconf rust qt6-base qt6-declarative flatpak ostree polkit gzip make desktop-file-utils gtk-update-icon-cache kservice kirigami xdg-utils plasma-integration xdg-desktop-portal xdg-desktop-portal-kde
cargo run
```

AppStream metadata comes from configured Flatpak catalog caches. Apps absent
from those caches still appear in Installed and can be removed. Adding a new
source refreshes its AppStream metadata and reloads the catalog without a restart.
Settings also provides an explicit Refresh; offline failures remain visible there.

## Install and register as the default handler

```sh
make
sudo make install
make set-default-handler
```

Run the last command **without sudo**, as the desktop user. It changes defaults
only for Flatpak files and supported Flatpak link schemes.

`make install` also merges those five associations into
`/etc/xdg/mimeapps.list` as system-wide defaults, preserving unrelated entries
and existing alternatives. Explicit per-user choices take precedence. The last
command above selects App Center for the current user as well.

For distro packaging:

```sh
DESTDIR="$PWD/fakeroot" make install
```

Staging writes the default associations only under `DESTDIR`; it does not change
the host's icon caches or MIME defaults. Override `SYSCONFDIR` for another
configuration prefix.

## Architecture

Rust reads/normalizes AppStream metadata. QML renders the Breeze light/dark
interface. The C++ Qt bridge exposes an asynchronous manager; an unprivileged
child process per install/removal lane runs libflatpak transactions and emits structured progress. It
resolves file/link preparation at `ready-pre-auth` and stops before deployment.
App-page sizes instead use local-only libflatpak metadata queries, without
starting that worker or storing a separate cache.
Actual installation proceeds directly after the app-page Install action;
uninstall and third-party software-source trust requests wait for the GUI's confirmation.
The worker never interpolates file names, app IDs or URLs into shell commands.
Removal consent is bound to the manager's exact installed app/scope/branch;
the worker revalidates that reference before force-stopping or removing it.
Direct worker callers still receive an explicit removal confirmation.

Mouse, touchpad, touch-screen scrolling and screenshot zoom remain independent
of the installation backend.
Screenshot thumbnails retain their hover highlight without an extra Preview
badge. Native touchpad pinches apply incremental zoom at the current focus,
without interpreting Qt's scene-coordinate translation as a pan. Releasing and
starting another pinch preserves the transform. Zoomed photos support held-click
dragging from mice and touchpads, including Wayland mouse-button events still
identified as TouchPad. Touchpad horizontal scrolling does not pan a zoomed photo
or change screenshots; browsing by swipe remains available when fitted. Mouse-wheel
zoom and touch-screen pinch/drag behavior are unchanged.

## Tests

Source-management tests never install or remove real apps. The native mirror
test writes only temporary repositories; the integration worker uses a
compile-time test settings path and Flatpak's temporary-installation overrides.
The optional online check downloads official Flathub metadata only. Merged-source
tests cover signing/policy equality, altered-source refusal, cancelled/denied
authorization preserving both copies, and explicitly restoring default sources.
In-use source tests create tiny offline app/runtime fixtures in fresh `/tmp`
installations, then compare every deployed file, export, commit and origin before
and after removing/restoring the source. User, default/named system and merged
scopes are covered; real desktop installations and repositories are untouched.
The production helper rejects non-root execution and arbitrary installation paths;
the policy requires active-session administrator authentication without cached grants.

```sh
c++ -std=c++17 -fPIC tests/native/test_sources.cpp -o target/test-sources $(pkg-config --cflags --libs Qt6Core flatpak ostree-1)
target/test-sources /var/lib/flatpak/repo/flathub.trustedkeys.gpg
c++ -std=c++17 -fPIC -pthread tests/native/test_source_worker.cpp -o target/test-source-worker $(pkg-config --cflags --libs Qt6Core Qt6Network flatpak ostree-1)
python3 tests/integration/test_sources.py target/test-source-worker /var/lib/flatpak/repo/flathub.trustedkeys.gpg --online
c++ -std=c++17 -fPIC tests/native/test_source_removal.cpp -o target/test-source-removal $(pkg-config --cflags --libs Qt6Core flatpak ostree-1)
python3 tests/integration/test_source_removal.py target/test-source-worker target/test-source-removal
# Root is needed only for the isolated system-installation fixtures:
sudo python3 tests/integration/test_source_removal.py target/test-source-worker target/test-source-removal --system
```

`tst_sources.qml` covers menu placement, Settings controls, removal confirmation,
single/multiple source choices, metadata switching, installed origins and small
windows. `SourcesSmoke.qml` captures native-themed pages without changing sources.
`BetaSourcesSmoke.qml` checks the real version, merged Flathub row and the empty
source dialog. `python3 tests/integration/test_source_policy.py` validates the
dedicated [Polkit executable action](https://polkit.pages.freedesktop.org/polkit/pkexec.1.html)
and authentication requirements; pass a staged installation root to check the
installed policy, helper permissions and MIT license too.

`SourceUiSmoke.qml` captures source checkboxes, both dialogs, real Installed
metadata and a pending local install in Queue; it changes no real repositories
or apps. Use a separate `XDG_RUNTIME_DIR` so it does not contact the live instance.
`test_source_picker.py` uses the real executable, QApplication and KDE platform
integration on a private bus with a mocked XDG FileChooser. It verifies the
repository filter, a real file containing spaces, selection, cancellation and
no Queue/source changes (requires `python-gobject`). The native Queue test uses
fake workers and temporary data to cover hidden source successes, failures,
cancellation/crashes and a visible local installation:

```sh
dbus-run-session -- python3 tests/integration/test_source_picker.py target/release/flufflinux-appcenter
"$(pkg-config --variable=libexecdir Qt6Core)/moc" src/flatpak_manager.h -o target/test-cancel-moc.cpp
c++ -std=c++17 -fPIC -pthread tests/native/test_source_queue.cpp src/flatpak_manager.cpp src/flatpak_sizes.cpp target/test-cancel-moc.cpp -o target/test-source-queue $(pkg-config --cflags --libs Qt6Core Qt6Gui Qt6DBus flatpak)
QT_QPA_PLATFORM=offscreen target/test-source-queue
```

On Fluff Linux:

```sh
cargo test
/usr/lib/qt6/bin/qmltestrunner -input tests/qml -import qml -platform offscreen
QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner -input tests/qml -platform offscreen
c++ -std=c++17 -fPIC tests/native/test_flatpak_sizes.cpp -o target/test-flatpak-sizes $(pkg-config --cflags --libs Qt6Core flatpak)
target/test-flatpak-sizes
target/test-flatpak-sizes --installed # Read-only validation against real deployed apps
c++ -std=c++17 -fPIC tests/native/test_transaction_status.cpp -o target/test-transaction-status $(pkg-config --cflags --libs Qt6Core glib-2.0)
target/test-transaction-status
```

Window preferences are tested using a temporary config (including creation,
live state changes, restart, minimizing, smaller screens and invalid values).
The same test can run under Wayland without any Flatpak operations or changing
the real user's preferences:

```sh
c++ -std=c++17 -fPIC tests/native/test_window_preferences.cpp -o target/test-window-preferences $(pkg-config --cflags --libs Qt6Quick Qt6Test)
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software target/test-window-preferences "$PWD/qml/Main.qml"
target/test-window-preferences "$PWD/qml/Main.qml"
```

`tests/qml/tst_focus.qml` checks mouse/touch empty-space focus clearing on
Catalog, Installed, app details and Queue, plus retained button/search
input, keyboard traversal, scroll drags and modal focus. Repeated menu dismissal
covers mouse/touch input on empty areas, Search and categories, including menus
opened by keyboard. Source tests cover initial/reopened information-dialog focus.

`tests/qml/tst_navigation_fit.qml` checks all 12 categories plus Installed across
six window sizes from 540 × 300 to 1920 × 1080, including resize recovery, label
bounds and working click targets. Run at 100%, 125%, 150%, 175% and 200% scaling.
The native typography test checks resolved system font families, bold metadata,
scalable rendering and visible glyph pixels (including the count digit 7), across
resizes and fractional scroll offsets. It can also run in the real Wayland session:

```sh
c++ -std=c++17 -fPIC tests/native/test_typography.cpp -o target/test-typography $(pkg-config --cflags --libs Qt6Widgets Qt6Quick Qt6Qml)
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_SCALE_FACTOR=1.5 target/test-typography "$PWD/tests/native/TypographyFixture.qml" target/typography-1.5.png
QT_QPA_PLATFORM=wayland target/test-typography "$PWD/tests/native/TypographyFixture.qml" target/typography-wayland.png
c++ -std=c++17 -fPIC tests/native/test_glyph_parity.cpp -o target/test-glyph-parity $(pkg-config --cflags --libs Qt6Widgets Qt6Quick Qt6Qml)
QT_QPA_PLATFORM=wayland target/test-glyph-parity "$PWD/tests/native/TypographyFixture.qml"
```

The glyph-parity test compares actual production count/source label pixels with
a TextInput reference at the same font, weight, color, baseline and position.
It covers `3297 applications`, `7 applications`, all digits and bold source text.
The optional `--native-labels` negative control intentionally restores the old
renderer and must fail on the fractional-scale Wayland reproducer; checking only
font family or absence of colored fringes was insufficient to detect this bug.

`tests/integration/NavigationFontSmoke.qml` uses the real launcher with fixture
data to capture wide/compact/short layouts, the information icon/dialog and a
dismissed menu. It performs no Flatpak operations or preference writes.

The native-touchpad regression sends Qt gesture events through the production
preview handler, including repeated releases, incremental updates and changing
focus points. It does not inject system input or start Flatpak operations:

```sh
"$(pkg-config --variable=libexecdir Qt6Core)/moc" tests/native/test_pointer_gestures.cpp -o target/test_pointer_gestures.moc
c++ -std=c++17 -fPIC tests/native/test_pointer_gestures.cpp -Itarget -o target/test-pointer-gestures $(pkg-config --cflags --libs Qt6QuickTest Qt6Quick Qt6Qml Qt6Gui)
QT_QPA_PLATFORM=offscreen target/test-pointer-gestures -input tests/native/gestures
```

The hover suite covers every category, selected/unselected states, Back, app
actions, Queue controls, search/sort controls, confirmation buttons and
preview controls in dark/light palettes. It sends enter/leave/re-enter events
over icon, label and padding, including after touch input, and samples rendered
page/popup pixels to verify the tint appears and disappears without changing focus
outlines. It also checks the rendered removal-button border on idle/hovered
Installed rows, disabled controls and keyboard focus. App-page tests check the
Back button's outer inset and hit target at narrow/wide widths. Run at both
100% and 150%, including the KDE style:

```sh
QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_hover.qml
QT_QPA_PLATFORM=offscreen QT_SCALE_FACTOR=1.5 QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_hover.qml
```

Sort and search-filter dropdowns own their label, arrow and background together.
KDE normally paints the non-editable label and arrow in its native background;
overriding only the background made both disappear. The shared control preserves
standard ComboBox selection, keyboard and accessibility behavior, and defaults
Installed sorting to Name: A–Z. The previous KDE keyboard-menu test failure is
also resolved. `tst_combo_display.qml` checks actual painted label/arrow pixels
for every sort and category choice in dark/light themes, plus keyboard and mouse
selection. `TextDropdownSmoke.qml` captures both selected controls and the exact
3297 input/count reproducer through the real launcher, without Flatpak operations.

`target/test-flatpak-sizes com.onepassword.OnePassword` prints the actual local
sizes and lookup time. `python3 tests/integration/test_local_sizes.py` compares
six local lookups (including 0 A.D. and Discord) with libflatpak's resolved plans without installing apps
(the reference plans require network access and a configured user Flathub).

For an end-to-end check, close App Center, then run the real executable with:

```sh
FLUFF_APP_CENTER_QML="$PWD/tests/integration/SizeSmoke.qml" target/release/flufflinux-appcenter
```

This clicks catalogue cards using the real backend, checks both visible labels,
enforces under 500 ms from opening to the completed page transition, and saves
screenshots in `target/size-proof-*.png`. It fails if the executable lacks the
size API instead of treating a newer QML/older executable mismatch as success.
The test needs the six apps above in the catalogue and not installed; Discord
also verifies hiding the redundant total when its dependencies are present.
The installed executable loads QML from its installation prefix, never from a
leftover build checkout. Install the executable and QML together with
`make install`; replacing QML alone does not update native features.

`FLUFF_APP_CENTER_QML="$PWD/tests/integration/CancelSmoke.qml" target/release/flufflinux-appcenter`
checks active and queued cancellation with the real worker, hidden status/history,
and retry without corrupting queue indices. It immediately cancels requests for
Calculator and Picker and refuses to run if either is already installed. Run on
the testing VM only; it never removes existing apps. Screenshots are saved in
`target/cancel-*-proof.png`.

`CancelDownloadSmoke.qml` runs the same checks after a real 0 A.D. app payload
has transferred at least 64 KiB, not just during startup. It verifies immediate
UI cancellation, worker exit plus refresh within two seconds, no installed test
app, and a successful cancel/retry cycle. It refuses preinstalled 0 A.D. and
Picker. Completed dependencies and reusable partial download data are retained.
`SizeUnitsSmoke.qml` performs that real-download/cancel check with an absent
1Password test app, also verifying matching MiB/GiB labels, MiB/s speed, foreground
progress text, and no completion count. It saves `target/binary-download-proof.png`.

Installation dates are saved locally after successful App Center installations,
separately from Queue history. Installed and app details show the date in the
system's locale and timezone, including the time but not the weekday; existing
apps without a record have no date row. App Center removes
the record on successful uninstall, so reinstalling records a new date.

`FLUFF_APP_CENTER_QML="$PWD/tests/integration/InstallProgressSmoke.qml" target/release/flufflinux-appcenter`
is a VM-only, real-worker UI test: it installs the absent Calculator app, checks
component progress, one monotonic overall bar, aggregate bytes, counts and completion
cleanup, checks dates in both views, and captures `target/unified-*-proof.png` and
`target/install-*-proof.png`. Its optional `sourceFile` property tests a local
bundle through the same app page. It leaves that test app installed for restart/date
verification; remove only that test installation afterward. Native persistence
tests run independently with:

```sh
c++ -std=c++17 -fPIC tests/native/test_install_history.cpp -o target/test-install-history $(pkg-config --cflags --libs Qt6Core)
target/test-install-history
c++ -std=c++17 -fPIC tests/native/test_transaction_progress.cpp -o target/test-transaction-progress $(pkg-config --cflags --libs Qt6Core)
target/test-transaction-progress
```

The manager's cancellation/crash regression uses fake protocol workers, never
installs or removes apps, and checks the forced-exit deadline, late-progress
suppression, next-job safety, retention of genuine crash errors, and cancellation
with stable job IDs after clearing history:

```sh
"$(pkg-config --variable=libexecdir Qt6Core)/moc" src/flatpak_manager.h -o target/test-cancel-moc.cpp
c++ -std=c++17 -fPIC -pthread tests/native/test_cancel_worker.cpp src/flatpak_manager.cpp src/flatpak_sizes.cpp target/test-cancel-moc.cpp -o target/test-cancel-worker $(pkg-config --cflags --libs Qt6Core Qt6Gui Qt6DBus flatpak)
QT_QPA_PLATFORM=offscreen target/test-cancel-worker
```

The parallel-worker regression uses a temporary installed-list fixture, fake
protocol workers and isolated history/cache paths. It covers overlapping
download/removal progress, confirmed pending removals, stale/overlapping review
tokens, cancellation isolation, sub-step completion before cleanup ends, and
discarding a stale installed list that returns after successful removal:

```sh
c++ -std=c++17 -fPIC -pthread tests/native/test_parallel_workers.cpp src/flatpak_manager.cpp src/flatpak_sizes.cpp target/test-cancel-moc.cpp -o target/test-parallel-workers $(pkg-config --cflags --libs Qt6Core Qt6Gui Qt6DBus flatpak)
QT_QPA_PLATFORM=offscreen target/test-parallel-workers
```

Successful-uninstall history cleanup has its own isolated fake-worker test.
Declining/failing removal retains history; unrelated apps and active job IDs
survive, and reinstall creates a new visible download entry:

```sh
c++ -std=c++17 -fPIC -pthread tests/native/test_removed_download_history.cpp src/flatpak_manager.cpp src/flatpak_sizes.cpp target/test-cancel-moc.cpp -o target/test-removed-history $(pkg-config --cflags --libs Qt6Core Qt6Gui Qt6DBus flatpak)
QT_QPA_PLATFORM=offscreen target/test-removed-history
```

`tests/integration/ParallelRemovalSmoke.qml` is an opt-in live VM check: it
requires 2048 and 0 A.D. to be absent, installs only 2048, then removes it during
a 0 A.D. download. It verifies received bytes continue increasing, cancels the
download, and checks both test apps are absent. Compare installed refs before
and after the run; do not run it while a user's transaction is active.

`tests/integration/ReviewLayoutSmoke.qml` is a non-destructive VM check for the
short uninstall title/paragraph, URL-sized website control and recorded local
date/time. It requires the configured app to be installed, pauses for a real
dialog screenshot, always answers **No**, and leaves its app details open.

After `InstallProgressSmoke.qml` exits, run
`FLUFF_APP_CENTER_QML="$PWD/tests/integration/UninstallSizesSmoke.qml" target/release/flufflinux-appcenter`
in a **new process** on the VM. It opens that test-created Calculator from its
installed metadata, declines removal once, then confirms removal and verifies
the real sizes are ready on the same page when Install reappears. It also checks
the installed page opens within 500 ms, hidden duplicate totals, and no removal
history/status. It saves `target/uninstall-sizes-proof.png`. Set `priorAppId` in
a wrapper to test that viewing another app first cannot redirect the refresh.
Only use this fixture for the disposable app created by the install test; it
removes that app and its data, not shared runtimes.

The integration suite really installs and removes GNOME Calculator, including
a data-deletion/fresh-install check. It refuses pre-existing Calculator
installations or data. Run **only on the testing VM**, as its desktop user:

```sh
APPCENTER_MUTATING_TESTS=1 python3 tests/integration/test_transactions.py
APPCENTER_MUTATING_TESTS=1 python3 tests/integration/test_uninstall_running.py
```

The running-app test uses the desktop user's real `XDG_RUNTIME_DIR`. It checks
that declining leaves two SIGTERM-resistant test sandboxes running, and accepting
force-stops both before deleting their app/data while unrelated apps keep running.

To verify launcher icon invalidation on the VM, build the read-only KDE probe:

```sh
c++ -std=c++17 -fPIC tests/native/icon_reload_probe.cpp -o target/icon-reload-probe -I/usr/include/KF6/KIconThemes $(pkg-config --cflags --libs Qt6Gui) -lKF6IconThemes
target/icon-reload-probe org.gnome.Calculator
```

Start it while that test app is absent, then install the app through App Center
in the same desktop session. The probe primes a missing-icon lookup and verifies
that its already-running KDE/Qt loader receives the reload notification and can
render the newly installed icon. It refuses an already-present icon and times
out without a notification. The test probe additionally needs `kiconthemes` headers.

It leaves shared runtimes available for subsequent tests and removes its test
application and temporary repository. A failed test reports its exact failure;
inspect installed state before retrying rather than deleting unrelated apps.
