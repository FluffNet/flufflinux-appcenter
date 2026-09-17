# App Center

A native Flatpak software center for Fluff Linux, built with Rust (standard
library only), QML, and the system Qt 6 and libflatpak libraries. There are no
background update services, notifications, settings, or tray components.

## Appearance

The page, header and sidebar share the KDE window color. Cards, fields and
dialogs share one subtly raised, opaque surface derived from it, without
independent blue-gray tints. Custom panels and controls use an 8-unit corner
radius; normal borders are 1 unit and keyboard-focus outlines are 2. Header
and sidebar separators meet once instead of stacking rectangle outlines, and
align to physical pixels at fractional scaling. The small application count
uses native font rendering while retaining the system's chosen font.

`tests/integration/StyleSmoke.qml` is a read-only visual check in the real KDE
session. It captures the catalog, Installed, app and Downloads pages plus native
and Qt-rendered count comparisons in `target/style-*.png`, then leaves the
catalog open. It does not start transactions or change the desktop theme, font
or scale. The QML styling tests also cover dark, light and custom palettes.

`tests/integration/AppMetadataSmoke.qml` is another read-only VM check: it
opens four real catalog apps, verifies their version/developer labels and
successfully loaded artwork, exercises the missing-icon fallback and recovery,
and captures `target/metadata-*.png`. It leaves 0 A.D.'s page open.

## Install and remove apps

- App pages show Size and Version in a compact stack beneath the developer, read from the
  same local catalog (no additional network request). Unknown versions are
  omitted; dependency totals appear below when needed. Large action buttons sit
  to the right, inset from the edge, with at least 176 × 56 logical-pixel touch
  targets. On narrow windows the buttons move below the information, while
  progress keeps its full width. The
  developer's name is displayed without a “By” prefix.
- App actions match the Downloads button's rounded neutral background, subtle
  border and icon-and-label layout. Install shares its arrow shape, in green;
  Open keeps the play icon and Uninstall the red trash icon. Hover, disabled and
  keyboard-focus states remain visible, without a solid accent fill.
- Catalog artwork uses Flatpak's stable `active` deployment path, not the
  disposable snapshot directory. A catalog refresh can no longer leave an
  already-open page pointing at deleted icons. Missing artwork falls back to
  the themed application icon on app pages, catalog cards, Installed and Downloads.
- Install from an app's information page. New apps, dependencies and software
  sources are installed **for the current user**, without administrator prompts.
  App Center's system-wide default-handler registration is separate from where
  Flatpaks are installed. The catalog's source and branch are preserved.
- On first use, an account without Flathub is offered the official signed
  Flathub source for that user. Other missing sources require their `.flatpakrepo`
  file; the app never silently falls back to a system installation.
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
  New software sources still require an explicit trust confirmation; source
  additions can remain after cancelling the later app installation. Missing
  local metadata shows unavailable sizes, never a fake zero. Installation still
  resolves the current plan normally, so actual transfers can differ from the
  repository's published estimates.
- Downloads keeps this session's jobs, per-dependency status, progress, and
  errors, with each app's icon beside its name (and a themed fallback when
  artwork is unavailable). Cancelled jobs disappear immediately from both Downloads and the app page.
  Cancellation signals Flatpak and closes the worker's input; a 250 ms watchdog
  stops that dedicated worker if it fails to exit. Late progress cannot revive
  the cancelled job, and a retry waits for worker exit/refresh before starting.
  Cancelling the only job also hides the Downloads
  button; other completed/failed jobs stay. Operations are serialized;
  additional requests wait in the queue.
  A single overall progress bar includes every planned component, with
  only a plain percentage below (no component-completion count). Progress text
  uses the normal foreground color: white in the dark theme, dark in the light
  theme. Above the bar, right-aligned
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
  Downloads retains component names/statuses
  but no extra component bars; the app page omits redundant activity/name text.
  Errors, cancellation and confirmation messages remain visible.
  Successful installs leave Open/Uninstall actions, not completion text,
  on the app page; their completed Downloads history remains available.
- Removals never appear in Downloads or its badge. Their progress/errors are
  shown in the Installed row and app view only; successful removal leaves no
  lingering completion text on the app page. Before Yes, both views show only
  “Waiting for confirmation”, without a progress bar. After Yes, removal progress
  appears without a Cancel button; install/download cancellation is unchanged.
- Installed lists user and system applications, with version and installed size.
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
opening a file/link does not install the app. Local bundles and new sources
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
sudo pacman -S --needed base-devel pkgconf rust qt6-base qt6-declarative flatpak gzip make desktop-file-utils gtk-update-icon-cache kservice xdg-utils
cargo run
```

AppStream metadata comes from configured Flatpak catalog caches. Apps absent
from those caches still appear in Installed and can be removed. Adding a new
source may require refreshing its AppStream metadata and restarting App Center
before its full catalog appears.

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
child process runs libflatpak transactions and emits structured progress. It
resolves file/link preparation at `ready-pre-auth` and stops before deployment.
App-page sizes instead use local-only libflatpak metadata queries, without
starting that worker or storing a separate cache.
Actual installation proceeds directly after the app-page Install action;
uninstall and software-source trust requests wait for the GUI's confirmation.
The worker never interpolates file names, app IDs or URLs into shell commands.

Mouse, touchpad, touch-screen scrolling and screenshot zoom remain independent
of the installation backend.

## Tests

On Fluff Linux:

```sh
cargo test
/usr/lib/qt6/bin/qmltestrunner -input tests/qml -import qml -platform offscreen
c++ -std=c++17 -fPIC tests/native/test_flatpak_sizes.cpp -o target/test-flatpak-sizes $(pkg-config --cflags --libs Qt6Core flatpak)
target/test-flatpak-sizes
c++ -std=c++17 -fPIC tests/native/test_transaction_status.cpp -o target/test-transaction-status $(pkg-config --cflags --libs Qt6Core glib-2.0)
target/test-transaction-status
```

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
separately from Downloads history. Installed and app details show the date in the
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
suppression, next-job safety and retention of genuine crash errors:

```sh
"$(pkg-config --variable=libexecdir Qt6Core)/moc" src/flatpak_manager.h -o target/test-cancel-moc.cpp
c++ -std=c++17 -fPIC -pthread tests/native/test_cancel_worker.cpp src/flatpak_manager.cpp src/flatpak_sizes.cpp target/test-cancel-moc.cpp -o target/test-cancel-worker $(pkg-config --cflags --libs Qt6Core Qt6Gui Qt6DBus flatpak)
QT_QPA_PLATFORM=offscreen target/test-cancel-worker
```

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
