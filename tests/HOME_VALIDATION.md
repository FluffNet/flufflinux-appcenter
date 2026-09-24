# Home/catalog validation — 2026-09-24

Tested on the KDE 6 Wayland VM with Qt 6.11.2 and Flatpak 1.18.2.

- Rust: 12 tests passed; optimized Linux build passed.
- Full QML regression suite: 422 passed, zero failures across 18 suites.
- Focused Home suite: 18 passed at both 100% and 150% scaling. Covers all eight
  orders, real zero versus unknown values, unavailable popularity, independent
  alphabetical recommendations, stable source identity, clicking recommendations,
  preserving All Apps position after asynchronous statistics arrive, and wheel
  return to recommendations.
- Layout cases: 720×520, 1180×520, 1400×1000 and 1920×1080 logical pixels. All
  nine recommended names remain untruncated; All Apps and at least the start of
  its first row remain visible without scrolling.
- Native CatalogStats tests passed: count validation, pagination consistency,
  oversized/malformed data rejection, cache loading, no request merely from
  constructing the data object. Home requests popularity presentation data on
  first display by default; this does not check for app updates.
- Native CatalogPreferences tests passed: all eight choices survive reload,
  invalid/missing settings default to popularity, window/unrelated entries remain
  unchanged, custom-QML fixtures use in-memory preferences, and actual Main.qml
  restores/saves/reloads the selected order across separate engine instances.
  The permanent popularity explanation is absent.
- Native manager regression passed: update checks remain explicit, selection,
  scope handling, cancellation, timeout/crash/malformed worker output, partial
  errors and duplicate prevention.
- Read-only real catalog test passed: exact exclusions hide an uninstalled app
  while preserving all catalog apps installed in the user/system installations;
  missing config uses bundled defaults; cached download sizes/release dates exist.
- Packaging test passed entirely in temporary directories: defaults, edited host
  exclusions inherited by fakeroot, explicit defaults-only override, preservation
  of administrator edits during a non-staged reinstall.
- Native Home smoke check passed on KDE/Wayland at 150% display scale. It showed
  Brave, Discord, Google Chrome, Minecraft Launcher, Sober, Spotify, Steam,
  Telegram and Visual Studio Code in that alphabetical order. Fresh HTTPS
  popularity fetch returned 3,300 valid app counts. The checked ordering began
  Sober, Firefox, Discord, Brave, Google Chrome. No app update check was started.
  Native wide, popular and narrow screenshots were visually inspected.

No regular Flatpak app was installed, updated or removed during this validation.
The existing AnyDesk, Steam, Flatpak Builder and system Firefox versions were
unchanged. Window preferences were also unchanged. The VM emits pre-existing Mesa
software-rendering warnings; the final native run had no QML binding/type errors.

Reproduction entry points are documented in README.md. Public popularity counts
and order naturally change over time; those are observed values, not test fixtures.
