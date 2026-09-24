# Home/catalog validation — 2026-09-24

Tested on the KDE 6 Wayland VM with Qt 6.11.2 and Flatpak 1.18.2.

- Rust: 12 tests passed; optimized Linux build passed.
- Baseline QML regression before the spacing refinement: 530 passed across 20 suites, including the final seven-test
  style rerun after making heading glyph rendering explicit. No failures remain.
  The search/sidebar regression now expects A–Z when opening a category instead
  of the old input-catalog order; search relevance assertions are unchanged.
- Category suite: 75 passed at both 100% and 150% scaling, including all six
  orders in all eleven categories, unknown values, live/offline popularity,
  recommendation retention, reset-on-category-switch, details/back navigation,
  Home/Installed/search/Updates independence and narrow/wide/short layouts.
- Publisher suite: 27 passed at both 100% and 150% scaling. Covers populated,
  markup-like and missing publisher names across recommendations, catalog cards,
  Installed, Updates, Queue and app details; shared color/weight/plain-text style;
  local metadata fallback with source/branch checks and `.desktop` identities;
  no invented repository/runtime publishers; bounded font fitting, two-line
  wrapping, repeated narrow/wide resizing, and full-name tooltips for extreme
  overflow. Recommended publishers sit two pixels below their titles with matching
  left edges, in a compact text group beside the icon; there is no separate footer.
  All nine real publisher names fit without elision while preserving app names
  and All Apps, including Microsoft Corporation and VinegarHQ & Sober contributors.
- Focused Home suite: 25 passed at both 100% and 150% scaling. Covers all six
  orders, real zero versus unknown values, unavailable popularity, independent
  alphabetical recommendations, stable source identity, clicking recommendations,
  no app counts on Home, categories, search or Installed, preserving All Apps
  position after asynchronous statistics arrive, and wheel
  return to recommendations. Both popularity orders omit only displayed
  recommendations (including Flatpak/AppStream aliases, alternate sources and
  offline fallback); name/date orders, search and categories retain them.
  An app reappears when no longer recommended. Home has no size options, Installed
  keeps size sorting, and app cards retain their name/summary without category tags.
- Layout cases: 720×520, 1180×520, 1400×1000 and 1920×1080 logical pixels. All
  nine recommended app and publisher names remain untruncated; text stays within
  the tile boundaries and above the readable minimum font size. All Apps and at
  least the start of its first row remain visible without scrolling.
- Home spacing refinement: 104 focused checks passed (Home 25 + publishers 27 at
  each of 100% and 150% scale). The gap below both All Apps and its sort control is
  24 logical pixels, or 16 in short windows, including when recommendations are
  unavailable. Header height includes the actual top inset instead of cancelling
  the bottom spacing. Native wide/narrow Home checks and screenshots confirmed
  the gap while keeping All Apps and the first app row visible.
- Native CatalogStats tests passed: count validation, pagination consistency,
  oversized/malformed data rejection, cache loading, no request merely from
  constructing the data object. Home requests popularity presentation data on
  first display by default; this does not check for app updates.
- Native CatalogPreferences tests passed: all six choices survive reload,
  invalid/missing and legacy size settings default to popularity (also checked
  against the real QML page), window/unrelated entries remain
  unchanged, custom-QML fixtures use in-memory preferences, and actual Main.qml
  restores/saves/reloads the selected order across separate engine instances.
  Changing category orders leaves the actual INI file byte-for-byte unchanged.
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
  Firefox, Bottles, Heroic, Flatseal, OBS Studio, with none of the nine recommended
  apps duplicated in either displayed group. No app update check was started.
  Native wide, popular and narrow screenshots were visually inspected.
  The same native run verified all six category orders against the real Internet
  catalog, preserved recommended apps in category results, reset category choices
  on navigation, and left Home's choice untouched. Wide and narrow category
  screenshots were visually inspected; no QML binding/type errors occurred.
  The publisher smoke run additionally matched the visible recommendation,
  catalog and installed labels against real metadata. Wide/narrow Home and
  Installed screenshots were visually inspected with the new publisher rows.
  The final adaptive-layout run additionally asserted that every real recommended
  publisher fits in both wide and narrow views; the title/publisher alignment
  and wrapped Sober/Microsoft publishers were visually checked at 150% display
  scale. Home, category and Installed app counts are absent in the native UI.
- Native font and pixel-parity checks passed at 150% scaling after moving their
  numeric probe from the removed count to the installed version label. Noto Sans
  stays in use; `3297`, `7`, all digits and `flathub (System)` match TextInput
  rendering with zero relative pixel error.

No regular Flatpak app was installed, updated or removed during this validation.
The existing AnyDesk, Steam, Flatpak Builder and system Firefox versions were
unchanged. Window preferences were also unchanged. The VM emits pre-existing Mesa
software-rendering warnings; the final native run had no QML binding/type errors.

Reproduction entry points are documented in README.md. Public popularity counts
and order naturally change over time; those are observed values, not test fixtures.
