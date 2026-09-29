# Desktop management links and local Flatpak files

Validated on the Fluff Linux KDE 6/Wayland VM on 2026-09-27.
Package: `flufflinux-appcenter 2026.9.0beta-10`.
Public version remains `2026.09 (Beta)`.

## Behavior

- KDE's existing menu is unchanged. Its AppStream links use the same executable
  with `--desktop-open`; no second executable or replacement menu was added.
- Desktop-opened AppStream IDs are checked against a fresh local Flatpak list.
  An installed match opens its details. Unknown IDs, catalog-only apps, malformed
  IDs and failed installed-list reads go to Home without an error dialog.
- Native pacman installations do not count as installed Flatpaks. If both native
  and Flatpak copies exist under the same ID, the installed Flatpak is opened.
- Exact IDs take priority; one unique case-insensitive match handles KDE URL
  normalization. Ambiguous matches do not select an arbitrary app.
- Home fallback clears search, category/MIME filters, About and old input errors.
- KDE does not identify its menu separately from other AppStream URL launchers,
  so the fallback applies to desktop-opened AppStream links generally. Direct
  CLI `--application` and positional app links retain normal catalog lookup.
- Local files bypass that installed-only check. The desktop entry still handles
  `.flatpak`, `.flatpakref` and `.flatpakrepo`, including multiple files and paths
  with spaces, non-ASCII names and URL-sensitive characters.

## Automated verification

- 28 Rust application tests and 2 source-text tests passed.
- 25 QML suites: 666 checks passed, zero failures.
- Native manager link tests verify fresh installed state, externally removed
  apps, failed reads, unknown/malformed IDs, catalog-only matches, mixed case,
  deferred startup loading, and no transactions or automatic update checks.
- The real executable/IPC CLI integration passed. Plain CLI missing-app errors
  are preserved while desktop management misses emit Home navigation instead.
- Actual desktop Exec activation passed through GIO, including all three file
  types, multiple files, spaces, Unicode, URL normalization and installed-only
  AppStream routing. Installed-package MIME defaults passed through `gio open`.
- Native background queue and isolated real add-on integration passed unchanged.
- Package metadata, desktop aliases, MIME registration and package integrity
  passed. `pacman -Qkk` reports 83 files with zero altered files.

## Real desktop/file verification

The installed executable, production UI and actual desktop associations were
tested in an isolated UI socket/config/cache, using the VM's real catalog and
installed Flatpak list. No install/remove confirmations were approved.

1. Unknown `org.invalid.DoesNotExist` opened Home.
2. Available but uninstalled HandBrake opened Home from an AppStream link.
3. Native Gwenview's ID opened Home.
4. Installed GIMP opened details with Uninstall, not Install.
5. The official HandBrake `.flatpakref`, downloaded into Downloads, opened
   HandBrake details with Install, not Home. It was not installed.
6. A genuine `.flatpak` bundle built from the retained isolated test repository
   opened the local-bundle trust confirmation. Cancel preserved installed refs.

The actual KDE application launcher was also searched for native Gwenview.
Right-clicking its result and selecting the unchanged "Uninstall or Manage
Add-Ons..." action launched the installed App Center on Home. A full desktop
screenshot records that result in `kde-menu-home-fallback.png`.

The two test files remain in `/home/mai/Downloads` for manual retesting:

- `App Center test - HandBrake.flatpakref`
- `App Center test bundle.flatpak`

Regular user/system Flatpak refs were identical before and after. The exclusions
checksum remains `ffb8212a6bb802afaf89980ff6d7e9cd7593d24af9f7242ab18c284b6731bbd9`.
Real screenshots are in `output/desktop-compatibility/`.

Initial harness issues were corrected without changing production behavior:
waiting for a QML close animation, accepting GIO's local-path/URL forms, using
nonempty MIME fixtures, accepting Flatpak's ref display format, and capturing a
QML-owned item rather than the window's native content root.
