# Updates validation — 2026-09-23

Test environment: Fluff Linux KDE/Wayland VM, Flatpak 1.18.2, Qt 6.11.2.

- Full QML regression suite after main-window Updates integration: **402 passed,
  0 failed** across 17 suites.
- Focused Updates QML suite: **12 passed at 100% and 12 passed at 150%**.
  Covers explicit-only checking, re-entry, cancellation, all-selected default,
  mixed/select-none/select-all, duplicate component totals, installation scopes,
  dates, errors, busy state, permission changes, pointer focus and small/large layouts.
  Also verifies the persistent sidebar/header, disabled and dimmed search,
  cancellation of pending searches, navigation back from Settings/Queue,
  selection preservation, matching native update icons and edge scrollbar.
- Native KDE/Wayland preview rechecked with the embedded Updates section at
  regular and minimum-size windows (150% display scaling), including actual
  isolated fixture results and the permission-change dialog. No app updates
  were applied; the preserved test releases remain available.
- Rust tests: **9 passed**.
- Native update-plan/permission/history assertions passed: additions, removals,
  missing metadata, environment-secret exclusion, changed commits/sources/actions,
  no-op plans, restarts, scope isolation and unchanged original install dates.
- Production manager with fake subprocesses: no automatic checks, exact `.desktop`
  IDs, user/system/named routing, selections, forged selection rejection, duplicate
  clicks, cancellation, timeout, worker crashes, invalid output and partial errors.
- Existing native manager regressions passed for permissions, removed Queue
  history, hidden source operations, parallel transaction lanes and cancellation.
- Actual offline Flatpak transactions passed: versions 1.0→2.0, positive byte
  estimates, changed/unchanged permissions, cancellation before deployment,
  stale plan/source rejection, selected-app isolation, shared runtime updates,
  persisted dates, no-op date preservation, empty result and restoring v1.
  Additional disabled/unreachable-source checks guard against a false up-to-date
  result. Explicit per-origin fetches are required because Flatpak's aggregate
  update-list helper can treat an unavailable origin as nonfatal.
- Native dark/light KDE previews captured and inspected; no new QML binding or
  reference errors. Settings checksum unchanged. Regular installed refs/commits
  were compared before/after metadata-only checking and remained identical.

The normal user/system scan found runtime updates, not app updates. Real system
deployment/Polkit interaction was not exercised; system/named update routing is
covered by simulations. No regular app or runtime was updated by these tests.
The final per-source scan correctly reports the existing missing system Flathub
source for Firefox/Flatpak Builder, rather than silently calling them current.
No source was added, removed or reconfigured in the regular installations.

Preserved test releases: `/home/mai/appcenter-update-fixtures/20260923` on the VM.
Both generations of each app/runtime are also backed up as `.flatpak` bundles.
The isolated installation is reset to v1. See `README.md` for repeatable commands.
