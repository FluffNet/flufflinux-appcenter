# App Center

**2026.09 (Beta)** · Copyright © 2026 FluffNet LLC · MIT License.
The Cargo package uses the equivalent SemVer `2026.9.0-beta`; `VERSION` holds
the user-facing release name shown by About.

A native Flatpak software center for Fluff Linux, built with Rust (standard
library only), QML, and the system Qt 6 and libflatpak libraries. There are no
automatic background update checks. An on-demand user service keeps active
transactions running after the window is closed, with native KDE tray progress.
Settings contains Flatpak source management.

## Build and prepare fakeroot

On Fluff Linux, with the build dependencies installed, run:

```sh
make fakeroot
```

This builds App Center and prepares **`fakeroot/`** with all installed files,
Discover compatibility symlinks, **`.PKGINFO`** and **`.INSTALL`**. It does not
create an archive, install anything, run package hooks or require sudo.
**You create the package manually.** Include the hidden metadata files when
packaging the directory. Re-running preserves the previous tree under
`build/fakeroot-backup.*/fakeroot` before replacing it with a fresh tree.

`.PKGINFO` declares `flufflinux-appcenter`, packager **FluffNet LLC**, all runtime
dependencies including `flufflinux-update`, and conflicts/replacements for both
`discover` and `flufflinux-discover`. Its template is `packaging/PKGINFO.in`.
`.INSTALL` comes from `packaging/INSTALL`: it registers Flatpak file handlers,
refreshes desktop/icon caches and reloads user-service definitions. It never
starts or enables App Center. Shared MIME defaults are merged, not packaged.

For a direct installation without making a package:

```sh
make
sudo make install
```

That copies the files into the system and runs the same install hooks. It does
not create or register a pacman package. Use `sudo make uninstall` to remove a
direct source install; its exclusions config is preserved. Direct installation
refuses to overwrite a package-managed Discover or App Center. Remove a direct
source install before switching to a package, without forcing file conflicts.

For source testing only, **`cargo run`** opens the app without installing it.
`cargo build --release` builds the main executable; `make` also builds its source
management helper. Neither command creates a package.

`sh tests/run_build_headers.sh` checks the source-helper and catalog headers with
compiler warnings treated as errors, without installing or running the helper.

## Discover replacement

The package keeps **`org.kde.discover.desktop`** as its visible desktop ID and
Wayland window identity, so existing Discover pins launch and group with App
Center. That old desktop file is a symlink to App Center's launcher, with App
Center's name/icon. `flufflinux-appcenter.desktop` remains a hidden compatibility
entry for existing file associations (not a second application-menu entry).
`flufflinux-appcenter` is the single executable for both GUI and CLI usage.
`plasma-discover`, `discover`, and `flufflinux-discover` are compatibility symlinks.
The old `flufflinuxplasmadiscover` and `plasmadiscover` icons are also symlinked to
the new icon, including for copied desktop shortcuts still using those names.
Locally customized shortcut names or absolute icon paths are not rewritten.
The old `--mode update` action opens **App Updates**, without starting a check.
Both old Flatpak and `appstream:` URL handler desktop IDs remain supported.
Discover's notifier is not carried over.

The build includes `/etc/flufflinux-appcenter/exclusions.conf` when present;
use `make fakeroot EXCLUSIONS_FILE=data/exclusions.conf` for bundled
defaults. Pacman tracks this as a backup configuration file, preserving edits
on upgrade. Shared `/etc/xdg/mimeapps.list` is not package-owned: install/remove
scripts merge only App Center's associations, preserving unrelated defaults.
Staging checks: `python3 tests/integration/test_pacman_package.py fakeroot`.
The same check accepts a manually created package archive instead of a directory.
`python3 tests/integration/test_fakeroot.py` checks staging and direct install
hooks in temporary directories without installing anything on the system.
Launcher dispatch: `python3 tests/integration/test_legacy_launch.py`.
The optional installed-KDE pin regression is `tests/native/test_discover_pin.cpp`.
Build it with Qt6Widgets/Qt6Qml flags, `-lKF6Service -ltaskmanager`, and include
paths `/usr/include/KF6/{KService,KCoreAddons,KConfig,KConfigCore}`. Run it in the
desktop session with the running window's reported desktop ID (`org.kde.discover`)
as its argument. It checks KDE's real launcher icon/name, window-to-pin matching,
and exactly one visible application-menu entry, without changing the panel.

## Command-line compatibility

The main executable and its three legacy aliases use the same parser and single-instance dispatcher.
For example, these open the same global search, including in an existing window:

```sh
flufflinux-appcenter telegram
flufflinux-appcenter --search "telegram"
plasma-discover telegram
plasma-discover --search "telegram"
```

Bare input defaults to search. Multiple words are joined, so
`flufflinux-appcenter google chrome` searches for "google chrome". Unknown flags
are also literal search text. A malformed recognized command, such as
`--mode=nope` or a missing option value, searches the entire input without
executing any partial command. Explicit `--search` text and extra bare words
are combined into one query. `--` stops option parsing but still distinguishes
recognized files/links from search text.

Recognized Flatpak file extensions and supported URL schemes retain their
existing input handling, including error messages when a file/link cannot be
opened. Input-size limits and the explicitly unsupported operations below
remain errors. No argument fallback installs an app or checks for updates.

Discover's public navigation and input options are supported:

- `--search TEXT`: global search (quote text containing spaces).
- `--application ID` or `--application appstream://ID`: open app details.
- `--category NAME`: sidebar names or raw AppStream categories such as `Game`,
  `Office`, `Viewer` and `InstantMessaging` (case-insensitive category matching).
- `--mime application/pdf`: apps declaring that exact MIME type in AppStream;
  names/descriptions are not used to guess support.
- `--mode Browsing|Installed|Search|Update|Sources|About`: case-insensitive;
  `--updates` is also supported. Update opens App Updates without checking.
- `--local-filename FILE`, or positional files/URLs: existing Flatpak input
  handling. Relative paths resolve in the caller's directory before forwarding.
- `--listmodes`, `--listbackends`, `-h`/`--help`/`--help-all`, `-v`/`--version`,
  `--author`, `--license`: terminal output without initializing the GUI.
- `--desktopfile NAME`: override a new window's desktop-entry base name;
  the default remains `org.kde.discover` to preserve taskbar pins.

Options also accept `--name=value`; `--` ends option parsing. Multiple initial
destinations follow Discover's priority: application, MIME, category, mode;
then search, local filename and positional inputs. App IDs are case-sensitive,
with an optional `.desktop` suffix. Unknown apps show an error rather than a
fabricated catalog card. Input links never directly install an app.

Two Discover-only operations are explicitly rejected, not silently ignored:
`--headless-update` (updates remain manually reviewed in App Updates), and
`--test FILE.qml` (Discover's private QML test environment is not available).
Generic Qt debugging flags are not emulated; use Qt environment variables such
as `QT_QPA_PLATFORM` and `QT_QUICK_CONTROLS_STYLE`. App Center is a Flatpak GUI,
not a replacement for the `flatpak` or `pacman` terminal administration tools.

Tests: `python3 tests/integration/test_cli.py`,
`tests/qml/tst_cli_navigation.qml`, `tests/native/test_application_links.cpp`,
and the existing legacy-launch/package/handler suites. CLI tests use isolated
config/cache/socket directories and never update or install apps.

## Home and catalog exclusions

Home shows **Common Apps** above **All Apps**, sharing the main page's
scrollbar. Compact name-and-icon tiles keep All Apps visible below them, including
at the minimum window size. The curated list is Brave, Discord, Google Chrome,
Minecraft Launcher, Sober, Spotify, Steam, Telegram, Visual Studio Code and Zoom, always
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
wrap onto two lines (up to three in the tightest Common Apps tiles). Common Apps
tiles keep publishers directly below their titles, sharing the same left edge
beside the icon. Curated publishers remain
readable without hovering even at the minimum window size, while keeping All Apps
visible. Exceptionally long metadata retains a readable font and uses a full-name
tooltip as the final overflow fallback. Home, category, search and Installed
headings omit the application count.

The sorting control is available on **Home and every catalog category**, with
A-Z/Z-A, most/least popular, and newest/oldest published release. Home defaults to
most popular. Each category starts at A-Z; its temporary choice resets when switching
categories and is never written to the config. Returning from app details resumes
the current category visit. Recommendations, search relevance and Installed sorting
are independent. Unknown values go last in both
directions; real zero install counts remain valid. Both popularity orders omit
apps currently shown in Common Apps, including when popularity is offline.
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
page explicitly falls back to A-Z. Download sizes and release dates come from
local Flatpak/AppStream metadata, not per-app network queries. Download sizes
exclude shared runtimes. None of these actions checks for app updates.

Edit **`/etc/flufflinux-appcenter/exclusions.conf`**, one Flatpak/AppStream ID
per line. Matching is case-insensitive; a trailing `.desktop` is optional.
Blank lines and `#` comments are supported. End an ID with `*` to exclude that
ID and every ID beginning with it: `org.winehq.Wine*` matches Wine and its related
IDs. Other wildcard positions and bare `*` are ignored. Matching uses the actual
Flatpak bundle ID and AppStream ID, never the displayed name or publisher.
The bundled list includes Wine, Fightcade's Wine component, Dolphin, Konsole,
VLC, Thunderbird, Kate, KWrite, Mission Center, Ark, Gwenview and LibreOffice.
**An installed Flatpak copy is never
hidden**: it remains visible/manageable and can receive updates. Otherwise the
exclusion removes it from Home, categories, search and recommendations. This is
a catalog presentation rule, not a security policy blocking direct file installs.
Restart App Center after editing the file, or use Settings' Refresh. App Center
re-evaluates the installed exception after its install/removal transactions.
An empty config disables exclusions; a missing/unreadable config uses the bundled
defaults. Installed system packages are not mistaken for installed Flatpak copies.

`make install` preserves an existing config. `make fakeroot` automatically copies
the host's edited exclusions into staging; if absent, it uses the bundled defaults.
Use `make fakeroot EXCLUSIONS_FILE=data/exclusions.conf` for defaults-only staging,
or point it at a curated file. Source uninstall preserves the config, and the
package metadata marks it as a backup configuration file.

Catalog tests: `sh tests/run_catalog.sh`, `sh tests/run_qml_suite.sh`,
`python3 tests/integration/test_catalog_exclusions.py` (read-only populated-catalog
check), and `python3 tests/integration/test_exclusions_packaging.py` (temporary
staging only). `tests/integration/HomeSmoke.qml` checks the native layout and live
public popularity data without checking for updates or changing installed apps.

## App Updates

### Network availability

App Center observes NetworkManager's system-bus properties while it is running.
When NetworkManager reports networking disabled or no active network connection
(including a machine with no network interfaces), **App Updates** is grayed out.
Home, categories and catalog search show **No Network Connection** with KDE's
themed `dialog-warning` triangle instead of app tiles. Installed apps,
their local search, Settings and the download queue remain accessible.

LAN-only, limited Internet, captive-portal and connecting states **show no note
and do not disable browsing or updates**. An unavailable or unknown
NetworkManager state also leaves actions enabled: it is not proof of being offline.
This uses NetworkManager's overall `State`, not `Connectivity=NONE`, which may
also occur on a working LAN without an Internet route. State definitions are in
the [NetworkManager API](https://networkmanager.dev/docs/api/latest/nm-dbus-types.html).

Availability comes from actual catalog loading, not an Internet connectivity
probe. If every enabled source fails and no usable catalog remains, Home,
categories and catalog search show **Cannot Connect to Sources**, the KDE warning
triangle, and **Please check your internet connection and try again.** A **Try
Again** button refreshes sources only; it never checks for app updates. Partial
success and cached catalogs remain browsable. A valid empty catalog, disabled
sources, a deliberately empty source list or a cancelled operation are not
classified as connection failures. Settings retains individual source errors.

Changes apply live. Losing the connection while Updates is open disables new
checks and the update action without discarding the list or selection; cancellation
of an existing check stays available. Reconnecting restores the controls but never
starts an update check. Catalog popularity may resume loading separately.
The observer only reads properties and listens for changes: no connectivity
probes, networking changes, privileged service, password prompt or NM autostart.

Network tests: `sh tests/native/run_network_status.sh` uses a private D-Bus daemon,
and `tests/qml/tst_network.qml` covers UI transitions with a mocked status source.
`sh tests/run_catalog_availability.sh` tests the production manager protocol and
real worker against isolated local repositories (no Internet or app changes).
`tests/integration/NetworkSmoke.qml` captures real KDE-rendered screenshots with
simulated statuses; it does not disconnect the host or change Flatpak apps.

### Checking and installing updates

**App Updates**, directly below Installed, shows an installed-style list in the main
window, keeping the sidebar and header visible. Search is grayed out and disabled
while App Updates is selected.
Opening/reopening the page, starting App Center, refreshing Installed, and
finishing transactions do **not** check for updates. Only **Check for App Updates**
starts the check. Loading, cancellation, timeout, and partial source errors are
visible; checking never enters Queue or deploys an app/runtime transaction.

The date line reads **Apps were last updated:** (or **Not recorded** when history
is unavailable). The last-check timestamp is not displayed.
The initial page has no redundant checking instructions or center prompt.
At narrow widths, the title and check button stack instead of overlapping.

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

Apps and runtimes are listed A-Z (apps first), selected by default. Each row
shows the installed and available version, source/branch, and download size
including required components, labeled **Size**. The selection summary reads
**N selected - Total size: …**. The selected total counts shared
components once. Actual transfers can be smaller because of cached data,
language subsets and deltas: initial sizes come from Flatpak's transfer estimate,
then both the row and selected total use resolved live transfer sizes as pulls
complete, like the normal install display. Missing published version labels use an explicit
commit revision instead of inventing a version. Version labels come from
Flatpak/AppStream; the selected update is checked against its reviewed commit.
Matching version labels append **(Refresh)** to the destination version.

Changed sandbox permissions have a **View Permission Changes** dialog showing
added and removed rules in the existing grouped layout. Unknown permission
metadata is explicitly unavailable, never “unchanged.” These are changes to
the app's declared permissions; existing overrides and portal grants are not
modified by the comparison.
Unchanged permissions have no status line; changed or unavailable comparisons
remain visible.

The action reads **Update All Apps** when every row is selected, otherwise
**Update selected apps**. It queues only the selected deployments. Queued rows
show **Queued…** in bold theme-foreground text without a progress bar. Active
updates reuse the same `InstallationProgress` component as app installs and the
queue: downloaded/total size, download speed, overall percentage and bar. Transfer
metrics disappear once downloading completes, while deployment activity continues.
Preparation, review, cancellation, failure and completion messages remain visible.
App Updates navigation and action icons use KDE's monochrome renderer with the
text foreground color, including in light themes; disabled controls still dim.
Required runtimes may
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
details below Website in the system's locale/timezone. Original install dates remain separate.
No-op, failed and cancelled-before-deployment updates do not acquire a new date;
a completed deployment is recorded even if a later operation fails. Previously
unobserved/external updates have no Last updated row in Installed or app details,
rather than guessing a date. The App Updates page still shows Not recorded when
no overall update history exists.

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

Service/CLI activation raises the existing window without restoring a maximized
window to normal. Reopening a hidden or minimized window preserves its last
normal/maximized choice. Home stays at the top while its header fills and
reflows, but does not reset a deliberate scroll when the window is resized.

The finished application list is saved as `application-list.json` in Qt's
per-user App Center cache directory under `$XDG_CACHE_HOME` (normally
`~/.cache`). Repeat launches show that list in the first frame without
`Loading...` and without contacting the sources or rebuilding.
The lifetime is strictly 12 hours from the last successful full source refresh
and catalog rebuild. At 12 hours or more, startup shows `Loading...`,
refreshes the actual enabled Flatpak/AppStream sources, then rebuilds and saves
the list. It does not show the expired list or refresh it in the background.
This updates catalog metadata, not installed apps, and does not check for app
updates. Conditional source responses confirming unchanged data are valid
refreshes; merely parsing existing local metadata is not.

Changes to Flatpak installations/deployments, source configuration, cached
AppStream metadata, source filters, exclusions or the App Center binary
invalidate the snapshot. Window size and sorting preferences do not. Source
initialization is skipped for a valid fresh snapshot. Settings' explicit source
refresh still rebuilds the list. Missing/corrupt/legacy caches require a full
source refresh too. Local rebuilds for installation/exclusion/source changes
preserve the last source-refresh timestamp instead of extending the lifetime.
Writes are atomic, and inputs changing during a parse cannot be saved as a
fresh snapshot. Cache write failures do not block browsing.
After a background queue finishes, the service waits for the local catalog
snapshot to be saved before exiting. Reopening then reuses the fresh list;
finishing an install/removal does not restart the 12-hour source-refresh timer.
This also applies to a normal X-button close during loading/saving. The worker
has one 30-second deadline covering parsing, saving and any unstable-input
retries. The GUI never performs the disk write. Timeout stops the worker and
releases background shutdown; it does not restart an endless retry loop.
An immediate reopen presents the same process and its in-memory app list while
the save continues. It starts neither a duplicate worker nor a source refresh;
closing again does not reset the original deadline.
Snapshots carry a SHA-256 integrity checksum. Truncated, altered or oversized
files are rejected. Atomic saving has direct-write fallback explicitly disabled,
so an interrupted or failed save leaves the previous good file untouched.
The in-memory list remains usable after a save failure; the next launch retries
the ordinary load/refresh path when no valid fresh snapshot is available.

Startup waits for NetworkManager's initial state before attempting an expired
refresh. Fully offline defers it until a connection appears; LAN-only, limited,
portal and unknown states allow an attempt. Failed source refreshes cannot
renew the cache. If all pulls fail, Home/categories show `Cannot Connect to
Sources` with Try Again; an offline machine shows `No Network Connection` and
disables App Updates. Partial success stays browsable without renewing the
whole-list cache. Source failures are in-app messages, not queue jobs or KDE
installation-failure notifications.

On a cold start the GUI appears before parsing finishes. Catalog loading runs
in the existing `--catalog` worker; launcher/IPC clients do not parse or rewrite
the catalog. Home displays `Loading...` only without a usable
snapshot, and early app links wait for the catalog. The service receives KDE's Wayland
activation token from the launcher so focus/startup feedback follows the window.
The launcher waits for the service's window-ready acknowledgement before exiting.
For timing diagnostics, `FLUFF_APP_CENTER_TRACE_STARTUP=1` prints elapsed
milliseconds for Qt initialization, QML loading, the first frame and the local
catalog. `tests/integration/StartupSmoke.qml` exercises real catalog arrival
without changing sources, installing apps or changing window preferences.
Run `python tests/integration/benchmark_startup.py target/release/flufflinux-appcenter --early`
inside the KDE Wayland session to measure the first frame and exercise a launch
request that arrives before it. The test uses a separate socket and closes its
own temporary window; it does not replace the installed package.
`python tests/integration/test_catalog_startup.py target/release/flufflinux-appcenter`
checks cold, warm and expired-cache launches against a temporary HTTP Flatpak
source. It publishes a new app, verifies a fresh cache makes no source request,
then expires the cache and proves the new app is downloaded and displayed.
`sh tests/run_catalog_availability.sh` also checks the exact 12-hour boundary,
offline deferral, LAN/limited attempts, refresh failure, local-rebuild age
preservation, invalidation and no redundant startup parsing.
`python tests/integration/test_catalog_queue_reopen.py /usr/bin/flufflinux-appcenter`
checks the installed binary with two tiny isolated local Flatpaks and a slow
post-queue parser. It verifies cached reopening and the unchanged refresh age.
Add `--reopen-during-save` to reopen during that pause, check the list stays
visible, close again and verify the same save still completes.
`python tests/integration/test_startup_cycles.py /usr/bin/flufflinux-appcenter`
measures 20 real GUI open/close cycles, alternating new processes with quick
reopening before idle exit. It uses the real catalog and a private IPC socket.
Centered loading, empty and error messages share bold, theme-foreground text,
including `No results.`; ordinary app descriptions remain secondary text.
Catalog loading shows only `Loading... 50%`, with no heading, bar or stage text.
This is weighted overall work progress, not a time estimate: source setup uses
0-10%, enabled source refreshes share 10-70%, catalog parsing uses 70-95%, and
serialization/cache finishing uses 96-99%. Only an accepted, completed list
reaches 100%. Values advance from real worker events, never a timer, and cannot
move backwards during a load or its bounded parser retries. Fresh-cache startup
still skips the loading screen entirely.
Flatpak's paired `appstream.xml` and `appstream.xml.gz` are read once, preferring
the already decompressed XML. Compressed-only catalogs are supported, and the
compressed copy remains a fallback if the plain file cannot be read. Different
sources and separate metadata files are not merged or skipped by this shortcut.
`python tests/integration/benchmark_catalog_dedup.py BEFORE_BINARY AFTER_BINARY`
alternates local-only catalog reads and checks complete catalog equality before
reporting timing differences; it never refreshes sources or rewrites caches.
`python tests/integration/test_catalog_progress_live.py target/release/flufflinux-appcenter`
measures a real clean Flathub pull followed by a cached launch in each theme,
using empty disposable data/config/cache roots and a private single-instance
socket. It limits only the test processes to two CPUs, records first-frame and
ready-frame timings, and saves real loading screenshots under `target/loading-*`.
The user's existing cache, sources, installed apps and desktop theme are untouched.

For live error screenshots, compile `tests/native/network_preview.cpp` with
Qt6Core/Qt6DBus into `target/network-preview`, then run
`python tests/integration/capture_catalog_failures.py target/release/flufflinux-appcenter`
inside KDE. NetworkManager states are simulated on a private bus; the production
worker attempts real Flathub through a refusing proxy, which records the attempted
requests. The VM's connection,
installed apps and real source/config files are unchanged. Captures go into
`target/cache-lan-source-failure.png` and `target/cache-fully-offline.png`.

Catalog and Installed scrollbars sit at the outer right edge for the full page
content height, with a persistent contrasting thumb and a minimum 44-pixel
drag target. Catalog cards share the available width and spare viewport height,
keeping consistent gaps without leaving a large empty band below the rows.
Scrolling retains its normal continuous movement and edge clipping: partially
visible cards are not hidden, and there is no row snapping.
Scrollbar thumbs remain directly draggable by touch as well as the mouse;
KDE's transient-touch setting cannot turn off their interaction.

The mouse's Back side button performs the same navigation as the page Back
button, preserving the previous catalogue position. It does not navigate behind
an open menu or dialog. Middle-click a scrollable page to start autoscrolling:
move above/below the anchor to choose direction and speed, and click again,
press Escape, or use the wheel to stop. Holding the middle button while moving
also scrolls, stopping on release. Leaving the view, switching pages or windows,
or opening a dialog stops it. The screenshot strip scrolls horizontally; other
pages and scrollable dialogs scroll vertically. The stopping click is consumed
so it cannot accidentally activate an app action underneath.

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
- Queue (formerly Downloads) keeps this session's app installations and updates,
  overall progress and errors. Each card identifies its action as Install or
  Update, including queued, completed and failed entries. Each app's icon is
  beside its name (with a themed fallback when
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
  Its sorting menu offers name A-Z/Z-A, installation date newest/oldest, and size
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
- `appstream:org.example.App` and `appstream://org.example.App` IDs.

Files and links open the app page with sizes and an Install button; merely
opening a file/link does not install the app. Local bundles and new third-party sources
retain their trust warning. Remote references are
limited to 2 MiB, with a bounded timeout and HTTPS-only redirects. Insecure HTTP
and URLs with embedded credentials are rejected. Signed Flatpak repositories
and bundle verification use libflatpak; private sources requiring additional
web/token login are not yet implemented.

The desktop entry accepts URLs with `%U`. A per-user socket forwards new files
and links to the existing App Center window, keeping one session's queue.

## KDE menu and app add-ons

KDE's application-menu **Uninstall or Manage Add-Ons** action opens the app's
`appstream://` link using the registered handler. App Center owns that handler
after installation. Desktop URL launchers may lowercase the ID, so App Center
first tries the exact ID and then one unique case-insensitive match. Ambiguous
matches are rejected. This opens details only; it never immediately uninstalls.
The route manages Flatpak applications, not pacman/system packages.

App pages show **Add-Ons** beside **View App Permissions** when their selected
source publishes AppStream add-on components extending that app. The dialog can
preview them before app installation. Install the parent app first to make
changes. App Center asks libflatpak which extensions match that exact installed
parent version, architecture and source; it does not guess by an ID prefix or
mix branches. Add-ons use the parent's user/system installation. Existing
Flatpak authorization policies apply to system-level changes.

Add-on installations use the normal queue, progress and background service.
Their Queue details link returns to the parent app, not a fake runnable runtime.
Removals require confirmation, stay outside Queue, and never delete sandbox data
or stop the parent app. Worker-side validation rejects substituted refs/scopes,
incompatible branches and a parent that changed since the dialog was loaded.
Browser extensions and plugins absent from Flatpak AppStream metadata are not
listed. Loading this dialog does not install anything or check for app updates.

`sh tests/run_addons.sh` covers desktop links, the QML dialog, and real isolated
Flatpak add-on installation/removal. `tests/integration/AddonsLive.qml` exercises
the actual dialog against that fixture and captures dark/light screenshots.

## Background app queue

Installed launches activate `flufflinux-appcenter.service` in the current user's
systemd session. The service owns the window and existing unprivileged Flatpak
workers; it is **not a root daemon**, an update checker, or a login autostart.
Closing the window hides it while pending work finishes. Starting App Center
again (including a Discover alias) reconnects to that same queue. An idle,
closed service exits automatically after a brief notification-delivery grace
period. Logging out, rebooting, or crashing is not a resumable-queue feature.

Only a genuinely closed window enables the App Center tray item and KDE
`KUiServerV2JobTracker` progress notifications. Minimizing does not. Reopening
silently removes those progress views without cancelling transactions or
reporting false success. The tray's Open action returns to App Center, including
any pending confirmation; background work never auto-approves a new prompt.
Native KDE jobs report the same overall percent, transfer size and speed as the
in-window queue. Multi-app batches show the current item's position, such as
`Installing 2/5: Telegram`, alongside its own progress bar. The same batch
position is shown above in-app progress bars. Old session history is not counted,
clearing history does not reset the position, and cancelled items leave the total.
Adding an installation while the queue is running updates the total immediately
in both places, for example from `2/5` to `2/6`, without restarting the active
transaction or replacing its native notification. Native notifications identify
all three actions as Installing, Updating or Removing. Removals stay outside the
Queue page and badge; their in-app progress remains in Installed and app details.
Waiting jobs are not shown as actively downloading. Success,
failure and cancellation use KDE's native completion semantics. A closed-window
multi-app batch produces one final KDE summary listing each app as installed,
updated, removed, failed or cancelled, instead of stacking per-app completions.
The summary is suppressed if the batch finishes with App Center open.

Plasma owns notification positioning and fullscreen/Do Not Disturb suppression.
No critical urgency, attention-requesting tray state or forced popup is used.
The standard KDE suspend inhibitor is requested whenever an installation,
update or confirmed removal is active/queued, whether the window is open or
closed. It is released when that work ends, including failure/cancellation, and
the D-Bus connection cleans it up on process exit. KDE's own power-management
policy (including its short activation grace period and user overrides) still
applies; screen locking and display blanking are not inhibited.

Regression tests: `sh tests/run_background.sh` uses real manager/controller/KDE
libraries with isolated fake workers, job-view service and power service under
`dbus-run-session`. For actual screenshots on the disposable KDE VM,
`APPCENTER_MUTATING_TESTS=1 python3 tests/integration/background_live.py` builds
and installs a real test Flatpak from a rate-limited localhost repository in a
fresh isolated installation. Add `--fullscreen` to verify KDE's inhibited state,
or `--desktop` to temporarily show the desktop for clean screenshots and restore
the other windows afterward. `--batch` installs five isolated apps and captures
the second app's real `2/5` progress. `--reopen` tests the same queue surviving a
close/open/close cycle. `--append` adds a sixth app during the second transfer,
captures `2/6` in Queue and KDE, and verifies all six apps finish.
These runs retain their test repositories, logs and actual Spectacle screenshots;
they never change regular user/system Flatpaks.

## Supported platform and dependencies

Fluff Linux (Arch-based), KDE Plasma 6, Wayland. No macOS or Windows builds.

```sh
sudo pacman -S --needed base-devel pkgconf rust qt6-base qt6-declarative flatpak ostree polkit gzip make desktop-file-utils gtk-update-icon-cache kservice kirigami xdg-utils plasma-integration xdg-desktop-portal xdg-desktop-portal-kde kcoreaddons kwindowsystem kjobwidgets kstatusnotifieritem systemd
cargo run
```

AppStream metadata comes from configured Flatpak catalog caches. Apps absent
from those caches still appear in Installed and can be removed. Adding a new
source refreshes its AppStream metadata and reloads the catalog without a restart.
Settings also provides an explicit Refresh; offline failures remain visible there.

## Default file handler

```sh
make set-default-handler
```

Run this optional command after installation **without sudo**, as the desktop
user. It changes defaults only for Flatpak files and supported Flatpak link schemes.

The shared `.INSTALL` hooks used by pacman and direct `make install` merge those
six associations into `/etc/xdg/mimeapps.list` as system-wide defaults, preserving unrelated entries
and existing alternatives. Explicit per-user choices take precedence. The
command above selects App Center for the current user as well.
`make fakeroot` only stages files; registration happens when the resulting
package is installed. Advanced `make install DESTDIR=...` copies the payload
without running hooks or adding shared MIME defaults to the staged file list.

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
While the screenshot viewer is visible, the underlying app page and thumbnail
strip cannot take a drag or wheel gesture. Opening the viewer stops any existing
flick, smooth-wheel animation or middle-click autoscroll without resetting the
background position. Closing it restores normal scrolling.

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

`tests/qml/tst_mouse_navigation.qml` and `tst_middle_scroll.qml` cover side-button
navigation, nested pages, popup/tooltip handling, middle-click and held-button
scrolling, stop gestures, bounds and nested horizontal scrolling.
`tests/integration/MouseControlsSmoke.qml` exercises the production pages in
KDE/Wayland using fake data, captures `target/mouse-autoscroll.png`, and exits.
It does not run Flatpak transactions. See `tests/MOUSE_VALIDATION.md` for results.

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

Native mouse events carry real elapsed timestamps. `tst_preview_drag.qml` first
scrolls the background page, then checks every step of the image drag at 125%,
200% and 400% zoom, normal/compact sizes, and center/edge positions. It checks
both mouse and held-touchpad input, repeat clicks, pending background motion and
restored scrolling after dismissal. Zero-timestamp events previously hid Qt's
timed background grab stealing; these tests must retain their event timing.

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
Installed sorting to Name: A-Z. The previous KDE keyboard-menu test failure is
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
