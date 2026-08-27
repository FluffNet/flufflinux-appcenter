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

- **Rust (standard library only):** reads Flatpak AppStream metadata and
  creates a small normalized catalog for the UI.
- **Qt 6/QML:** renders the responsive Plasma-native interface through a tiny
  native bridge compiled directly against the system Qt libraries.
- **Flatpak metadata:** uses the AppStream catalogs downloaded from configured
  Flatpak remotes such as Flathub.

## Visual design and themes

The interface follows the Fluff Linux design language established by
`fluffsetup` and `fluffinstall`: spacious layouts, layered surfaces, strong
headings, and the Fluff red accent. It still respects the active Breeze color
scheme. Text, panels, borders, hover states, focus contrast, and the flat
background update automatically from the Qt palette when the Plasma theme
changes.

The Rust package has no third-party crate dependencies.

## Requirements

```sh
sudo pacman -S --needed base-devel pkgconf rust qt6-base qt6-declarative flatpak gzip make
```

AppStream metadata is read from Flatpak's system and per-user catalog
directories. The native Qt bridge sets the correct Plasma application identity
and injects the catalog directly into QML.

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
