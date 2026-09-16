# App Center

A native Flatpak software center for Fluff Linux, built with Rust (standard
library only), QML, and the system Qt 6 and libflatpak libraries. There are no
background update services, notifications, settings, or tray components.

## Install and remove apps

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
  repository metadata, not installed disk usage. Dependencies already available
  in the user or system installation are excluded. Opening an app reads this
  metadata directly before showing the page: no network transaction, waiting
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
  errors. Cancelled jobs disappear from both Downloads and the app page once
  cancellation finishes. Cancelling the only job also hides the Downloads
  button; other completed/failed jobs stay. Operations are serialized;
  additional requests wait in the queue.
  The overall bar includes every planned component; the status below identifies
  the current app/dependency and preserves Flatpak's download/install phase.
  Its live byte count is for that component, not the whole transaction. Published
  estimates can exceed actual transfers, notably for locale subsets and reused
  content. Successful installs leave Open/Uninstall actions, not completion text,
  on the app page; their completed Downloads history remains available.
- Removals never appear in Downloads or its badge. Their progress/errors are
  shown in the Installed row and app view only; successful removal leaves no
  lingering completion text on the app page.
- Installed lists user and system applications, with version and installed size.
  Open an app, view its information, or uninstall it from its row or app page.
- Uninstall asks a compact **Yes / No** question naming the app and data deletion.
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

Installation dates are saved locally after successful App Center installations,
separately from Downloads history. Installed and app details show the date in the
user's locale; existing apps without a record have no date row. App Center removes
the record on successful uninstall, so reinstalling records a new date.

`FLUFF_APP_CENTER_QML="$PWD/tests/integration/InstallProgressSmoke.qml" target/release/flufflinux-appcenter`
is a VM-only, real-worker UI test: it installs the absent Calculator app, checks
component progress and completion cleanup, checks dates in both views, and captures
`target/install-*-proof.png`. It leaves that test app installed for restart/date
verification; remove only that test installation afterward. Native persistence
tests run independently with:

```sh
c++ -std=c++17 -fPIC tests/native/test_install_history.cpp -o target/test-install-history $(pkg-config --cflags --libs Qt6Core)
target/test-install-history
```

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
