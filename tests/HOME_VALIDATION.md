# Home/catalog validation — 2026-09-24

Tested on the KDE 6 Wayland VM with Qt 6.11.2 and Flatpak 1.18.2.

- Rust: 16 tests passed; optimized Linux build passed.
- Baseline QML regression before the spacing refinement: 530 passed across 20 suites, including the final seven-test
  style rerun after making heading glyph rendering explicit. No failures remain.
  The search/sidebar regression now expects A–Z when opening a category instead
  of the old input-catalog order; search relevance assertions are unchanged.
- Category suite: 75 passed at both 100% and 150% scaling, including all six
  orders in all eleven categories, unknown values, live/offline popularity,
  recommendation retention, reset-on-category-switch, details/back navigation,
  Home/Installed/search/Updates independence and narrow/wide/short layouts.
- Publisher suite: 29 passed at both 100% and 150% scaling. Covers populated,
  markup-like and missing publisher names across recommendations, catalog cards,
  Installed, Updates, Queue and app details; shared color/weight/plain-text style;
  local metadata fallback with source/branch checks and `.desktop` identities;
  no invented repository/runtime publishers; bounded font fitting, two-line
  wrapping (three lines in the tightest Common Apps tiles),
  repeated narrow/wide resizing, and full-name tooltips for extreme
  overflow. Common Apps publishers sit two pixels below their titles with matching
  left edges, in a compact text group beside the icon; there is no separate footer.
  All ten real publisher names fit without elision while preserving app names
  and All Apps, including Microsoft Corporation and VinegarHQ & Sober contributors.
- Focused Home suite: 28 passed at both 100% and 150% scaling. Covers all six
  orders, real zero versus unknown values, unavailable popularity, independent
  alphabetical recommendations, stable source identity, clicking recommendations,
  no app counts on Home, categories, search or Installed, preserving All Apps
  position after asynchronous statistics arrive, and wheel
  return to recommendations. Both popularity orders omit only displayed
  recommendations (including Flatpak/AppStream aliases, alternate sources and
  offline fallback); name/date orders, search and categories retain them.
  An app reappears when no longer recommended. Home has no size options, Installed
  keeps size sorting, and app cards retain their name/summary without category tags.
- Layout cases: 720×520, 720×640, 720×760, 1180×520, 1400×1000 and 1920×1080
  logical pixels. All ten common app and publisher names remain untruncated; text stays within
  the tile boundaries and above the readable minimum font size. All Apps and at
  least the start of its first row remain visible without scrolling.
- Home spacing refinement: 104 focused checks passed (Home 25 + publishers 27 at
  each of 100% and 150% scale). The gap below both All Apps and its sort control is
  24 logical pixels, or 16 in short windows, including when recommendations are
  unavailable. Header height includes the actual top inset instead of cancelling
  the bottom spacing. Native wide/narrow Home checks and screenshots confirmed
  the gap while keeping All Apps and the first app row visible.
- Common Apps refinement: 112 focused checks passed (Home 27 + publishers 29 at
  each of 100% and 150% scale). The heading is Common Apps, and `us.zoom.Zoom`
  is the tenth alphabetical tile, filling the second row at five columns.
  Short windows use at least four columns to preserve All Apps and its first row;
  tight tiles adapt their icons, titles and publisher wrapping within readable
  bounds. Zoom opens its own app details, is omitted from both Home popularity
  orders while shown in Common Apps, and remains in name/date/category/search
  results. No app installation or source change is triggered by its inclusion.
- Popularity label refinement: Home and category menus show “Most popular: First”
  and “Least popular: First”. The saved `popularity-desc`/`popularity-asc` keys,
  sort directions and temporary category choices are unchanged. Home 28 and
  category sorting 75 passed at each of 100% and 150% scale (206 checks total).
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
- ID exclusions: unit tests cover case-insensitive exact IDs, `.desktop` aliases,
  a trailing `*` matching the ID and all IDs beginning with it, invalid-pattern
  rejection, no substring/name matching, differing AppStream/Flatpak bundle IDs,
  and the installed exception retaining the actual Flatpak ID spelling.
  Read-only real catalog tests passed for exact and prefix rules, preserving all
  catalog apps installed in user/system installations. File and bundled defaults
  agree, including ten currently available excluded IDs: Mission Center, Ark,
  Dolphin, Gwenview, Kate, Konsole, KWrite, LibreOffice, Thunderbird and VLC.
  Thunderbird's lowercase catalog ID matches the mixed-case config entry. Wine
  and Fightcade's Wine component are absent from the current catalog; their ID
  rules are covered by unit tests. Missing config uses bundled defaults; cached
  download sizes/release dates remain available.
  The installed `/usr/bin/flufflinux-appcenter` passed the same checks, including
  an explicit comparison against the active `/etc/flufflinux-appcenter/exclusions.conf`.
  Native Home smoke checks passed with the full list enabled; regular Flatpak
  versions were unchanged after deployment and App Center restarted successfully.
- Packaging test passed entirely in temporary directories: defaults, edited host
  exclusions inherited by fakeroot, explicit defaults-only override, preservation
  of administrator edits during a non-staged reinstall.
- Native Home smoke check passed on KDE/Wayland at 150% display scale. It showed
  Brave, Discord, Google Chrome, Minecraft Launcher, Sober, Spotify, Steam,
  Telegram, Visual Studio Code and Zoom in that alphabetical order. Fresh HTTPS
  popularity fetch returned 3,300 valid app counts. The checked ordering began
  Firefox, Bottles, Heroic, Flatseal, OBS Studio, with none of the ten common
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
