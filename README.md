# Fluff Linux App Center

A focused, native application catalog for Fluff Linux, built with Rust and
Qt 6/QML. It provides the window, searchable catalog, category layout, and app
details view—without update services, notifications, settings, or tray code.

## Supported platform

Fluff Linux App Center is intentionally built only for **Fluff Linux**, based
on Arch Linux, running **KDE Plasma 6 on Wayland**. macOS, Windows, X11-only
desktops, other Linux distributions, and cross-compilation are not supported
targets. The build fails immediately on a non-Linux host.

## Design

- **Rust (standard library only):** reads installed AppStream metadata and
  creates a small normalized catalog for the UI.
- **Qt 6/QML:** renders the responsive Plasma-native interface.
- **System metadata:** uses AppStream catalogs already supplied by Arch Linux,
  Flathub, and other configured software sources.

The Rust package has no third-party crate dependencies.

## Requirements

```sh
sudo pacman -S --needed rust qt6-declarative appstream gzip make
```

`qml6` or `/usr/lib/qt6/bin/qml` must be present. AppStream metadata is read
from the standard system catalog and metainfo directories.

## Run from the source tree

```sh
cargo run
```

## Build and stage for packaging

```sh
make
DESTDIR="$PWD/fakeroot" make install
```

The staged files will be placed under `fakeroot/usr/`.

## Scope of the first release

- Browse all applications
- Search by name, summary, description, or category
- Filter using a compact category sidebar
- Open a complete app details page with metadata and screenshots

Installation and removal are deliberately outside this initial catalog-only
milestone.
