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
- Before deployment, review Flatpak's resolved app/dependency list and estimated
  download sizes. Existing shared runtimes are reused. New sources require a
  separate trust confirmation; source additions can remain after cancelling the
  later app installation.
- Downloads keeps this session's jobs, per-dependency status, progress, errors,
  and cancellations. App pages show the same live progress. Operations are
  serialized; additional requests wait in the queue.
- Installed lists user and system applications, with version and installed size.
  Open an app, view its information, or uninstall it from its row or app page.
- Uninstall confirms removal and deletes **the current user's sandbox directory**
  at `~/.var/app/APP_ID`, then resets that app's portal permissions. This deletion
  is irreversible. Other users' data, documents saved elsewhere, and shared
  runtimes are not deleted. If cleanup fails, the job reports an error instead
  of claiming a fresh uninstall. Close the app before uninstalling.
- Flatpak refreshes the installation's exported desktop/icon caches. App
  Center additionally rebuilds Plasma's application cache, invalidates its
  cached icons, and reloads installed metadata after every transaction.
- Run the app as your **regular desktop user**, never root. Existing system apps
  remain visible. Uninstalling one explicitly warns that it affects all users
  and may require normal desktop authorization; new installations never do.
- Closing while work is active asks you to wait or cancel. Cancellation does not
  roll back dependency operations that already completed.

## Local files and browser links

Use **Open Flatpak…**, drop files onto the window, or pass them on the command
line. Supported inputs:

- Local `.flatpak` bundles, `.flatpakref` references and `.flatpakrepo` sources.
- HTTPS references, including `flatpak+https://…` browser links.
- `flatpak:org.example.App` and `flatpak://org.example.App` IDs.

Local bundles and references still require confirmation. Remote references are
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
pauses at the actual transaction plan until the GUI replies to the review.
The worker never interpolates file names, app IDs or URLs into shell commands.

Mouse, touchpad, touch-screen scrolling and screenshot zoom remain independent
of the installation backend.

## Tests

On Fluff Linux:

```sh
cargo test
/usr/lib/qt6/bin/qmltestrunner -input tests/qml -import qml -platform offscreen
```

The integration suite really installs and removes GNOME Calculator, including
a data-deletion/fresh-install check. It refuses pre-existing Calculator
installations or data. Run **only on the testing VM**, as its desktop user:

```sh
APPCENTER_MUTATING_TESTS=1 python3 tests/integration/test_transactions.py
```

It leaves shared runtimes available for subsequent tests and removes its test
application and temporary repository. A failed test reports its exact failure;
inspect installed state before retrying rather than deleting unrelated apps.
