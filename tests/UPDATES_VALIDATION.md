# Updates validation — 2026-09-23–24

Test environment: Fluff Linux KDE/Wayland VM, Flatpak 1.18.2, Qt 6.11.2.

## Search/menu order and update history cleanup — 2026-09-24

- Removed Last checked from the App Updates page, including after a completed
  check. Apps were last updated remains visible; backend bookkeeping is unchanged.
- Search now precedes the three-dot menu. The dropdown is aligned to the right
  edge of its button so it stays inside the window. Search width uses the actual
  header content width, preserving clearance from Queue at minimum window size.
- At both 100% and 150% scale: Updates 18 passed, Network 47 passed, Search Input
  12 passed, Focus 90 passed, and the selected Sources menu-layout test 4 passed
  (171 per scale, 342 total). Header geometry covers narrow/wide windows, Queue
  visible/hidden, and offline/online states. Settings/About interactions still pass.
- AppUpdatesLabelsSmoke.qml passed on KDE/Wayland, capturing normal and compact
  screenshots with a recorded update date and no Last checked line. Search/menu
  geometry is asserted; the real backend stays idle. No Flatpak apps were updated.

## Centered checking indicator — 2026-09-24

- Spinner and Checking for app updates text are centered together in the main
  results area, below the header/history. Cancel remains in the header.
- Geometry assertions at 720, 1180 and 1920 widths verify both axes, text fit,
  spinner activity, hidden result rows, cancellation, and navigation away/back.
  The animation stops when its page is hidden or checking ends.
- App Updates suite: 18 passed at both 100% and 150%; network suite: 47 passed
  at both scales. Mouse tests wait for the new Cancel layout to render before
  clicking; all cancellation assertions are retained.
- Real KDE normal/compact screenshots from AppUpdatesCheckingSmoke.qml use a
  simulated pending check and assert the real backend remains idle. No app
  updates, source changes or actual update checks were performed.

## App Updates wording — 2026-09-24

- Sidebar, heading and check button explicitly say App Updates. Offline advice,
  empty/result statuses, worker status and errors consistently refer to app updates.
- Removed the initial checking explanation and center prompt. Date history reads
  Apps were last updated; missing history says Not recorded. Last checked remains
  visible after a check; timestamps and update scheduling were not changed.
- Updates, navigation-fit and network suites: 71 passed at each of 100% and 150%.
  Updates was rerun at both scales with additional title/button non-overlap checks:
  15 passed each. Widths 720, 1180 and 1920 retain visible, usable controls.
- Native production-manager regression passed, including explicit-only checks,
  selection, scopes, cancellation, timeout, crash and partial-error handling.
- Rust: 16 passed. Optimized Linux build passed.
- AppUpdatesLabelsSmoke.qml rendered the actual KDE page at normal and minimum
  size, checked labels/history/empty center and captured both screenshots. It
  asserted the backend stayed idle: no update scan or app mutation was performed.

## Earlier update functionality validation

- Full QML regression suite after source-recovery changes: **403 passed,
  0 failed** across 17 suites.
- Focused Updates QML suite: **13 passed at 100% and 13 passed at 150%**.
  Covers explicit-only checking, re-entry, cancellation, all-selected default,
  mixed/select-none/select-all, duplicate component totals, installation scopes,
  dates, errors, busy state, permission changes, pointer focus and small/large layouts.
  Also verifies the persistent sidebar/header, disabled and dimmed search,
  cancellation of pending searches, navigation back from Settings/Queue,
  selection preservation, matching native update icons and edge scrollbar.
  Unavailable sources are shown as skipped, never selectable or falsely current.
- Source restoration policy assertions cover official stable/beta definitions,
  user/system/named scopes, missing user source, unverified/disabled sources,
  URL spoofing, channel mismatches, existing-source collisions and no re-enabling.
  Manager tests cover source-list publication and invalidation of stale updates.
  Existing signed-source mirroring/grouping and user-install routing tests passed.
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
  Additional missing/disabled/unreachable-source checks verify zero offered
  updates for those origins and guard against a false up-to-date result.
  Explicit per-origin fetches are required because Flatpak's aggregate
  update-list helper can treat an unavailable origin as nonfatal.
- Native dark/light KDE previews captured and inspected; no new QML binding or
  reference errors. Settings checksum unchanged. Regular installed refs/commits
  were compared before/after metadata-only checking and remained identical.

The initial user/system scan found runtime updates, not app updates. Real system
deployment/Polkit interaction was not exercised; system/named update routing is
covered by simulations. No regular app or runtime was updated by these tests.
The final per-source scan reports Firefox/Flatpak Builder as skipped when their
system Flathub source cannot be restored, rather than silently calling them current.
No source was added, removed or reconfigured during those initial tests.

The opt-in real-desktop recovery test reached KDE's configure-remote authorization,
then safely timed out because authentication was not completed in the VM. Both
attempts preserved the missing source, skipped the system apps and retained only
healthy user-source candidates. A successful privileged restoration remains to
be verified after administrator authorization; at that point the source-recovery
build had not replaced the installed build. The ordinary apps' commits and settings hash
were unchanged.

Read-only authorization checks against the running desktop App Center process:
`org.freedesktop.Flatpak.app-update` returned authorized (exit 0) without interaction;
`org.freedesktop.Flatpak.configure-remote` returned authentication required (exit 2).
The installed policy allows signed app updates in an active desktop session, but
source configuration requires administrator authentication. SSH/inactive sessions
are different. No authorization rules were changed.

## Authorized deployment and source restoration — 2026-09-24

- After explicit approval to use the saved VM login and administrator credentials,
  installed the tested `c1e0e89` binary and matching Updates page. The previous
  binary/page were preserved at `/tmp/appcenter-before-source-fix.TMRKSE` on the VM.
  Live binary SHA-256:
  `69f5c8b43ae741c763c2ab0b40797e292315ee7d610f5c5d00ce0fa421ddf5d3`.
- Restored system Flathub using its official `.flatpakrepo` definition with normal
  administrator authorization. This was a one-time command-line restoration;
  successful completion of the GUI Polkit recovery remains untested. Earlier
  GUI attempts did reach authentication and handle its timeout safely.
- Installed-binary, real-desktop `SystemSourceSmoke.qml` check passed:
  `state: ready`, `error: ""`, `skipped: []`. User and system Flathub appeared in
  one merged source row, with user-only Flathub Beta remaining separate. The
  missing-source message was absent. The scan offered the system Firefox update,
  its locale component, and user GNOME runtime/locale updates.
- Corrected the smoke harness to request the source list explicitly when no
  restoration is needed, and emit an explicit pass/fail marker in addition to
  the QML exit request. An empty, not-yet-loaded source list is not evidence of
  a grouping failure, and process exit status alone is not the test assertion.
  Successful verification invocation: `575d33ae5d9b4fb28e50ab804515b138`.
- Rechecked `org.freedesktop.Flatpak.app-update` authorization against the newly
  running desktop App Center process: exit 0 without interaction. Existing signed
  system app updates are authorized without a password in the active desktop
  session; adding a system source is a separate administrator-authorized action.
  No Polkit rules were altered, and no system app deployment was needed to check
  that authorization.
- No regular apps or runtimes were updated. AnyDesk, Steam, Firefox and Flatpak
  Builder commits were unchanged, as was the App Center settings checksum.
  The live App Center service was restarted successfully.

## Actual passwordless system update — 2026-09-24

The user's subsequent Firefox update exposed a gap in the earlier authorization
check: the worker passed an explicit commit to `flatpak_transaction_add_update`.
Flatpak rejects arbitrary-commit selection for a non-root system update even
when that commit is the newest release. An authorized `app-update` action alone
does not test this transaction restriction.

- Changed the transaction to request the normal latest release (null commit).
  The existing `ready-pre-auth` callback still verifies every resolved operation
  against the selected commit/source/action plan before allowing deployment.
  Missing, disabled or changed sources and unreviewed releases remain rejected.
  No new root service, password automation, or Polkit changes were added.
- Added a real offline regression that publishes a new release after the check:
  the fixed worker rejects it without changing any installed fixture commits.
  Verified red/green behavior: the old installed binary fails this regression;
  the fixed binary passes the complete update suite. Cancellation, selected-only
  deployment, shared runtimes, history, no-op handling and v1 restoration pass.
- Rust: **9 passed**. Focused Updates QML: **13 passed at 100% and 13 at 150%**.
  Full QML regression suite: **403 passed, 0 failed** across 17 suites.
- With the user's authorization to test regular Flatpaks, used the opt-in
  `SystemUpdateSmoke.qml` to select only system Firefox and press Update Selected
  through the actual App Center UI/backend. It required unchanged permissions,
  no other application in the plan, successful completion, the new installed
  version and a persisted update date. No confirmations were auto-accepted.
- **Actual system Firefox update passed without a password prompt**:
  `156.0` → `156.0.1`, old commit
  `88680ed733657bf8eb654fa14ce6c67cb319a81987adf5acf01be7b0b6e18b49`
  → `48ccd343a9f0a1d623720bad300e4398323fcfa2e155713fb75d3e0b745926f8`.
  `SYSTEM_UPDATE_PASS` recorded `updatedAt: 2026-09-24T09:39:17.921Z`.
  Desktop test invocation: `d25fb2d8c3e746edbb2ae15f4eb4ea4e`.
  Flatpak's existing system helper journal confirms the application deployment.
  The Firefox process was left running, and other app commits/settings stayed
  unchanged. Restart Firefox normally to run the updated release.
- Before the update, preserved Firefox 156.0 as an independent archive repository
  and `.flatpak` bundle at
  `/home/mai/appcenter-update-fixtures/firefox-before-update.x2Agmu` on the VM.
  Bundle SHA-256: `6966807b37facbd6f42348a385147d9cbfe16baeb8862e8540b6e3f16dcd4e03`.
- Installed and restarted the verified build. Installed binary SHA-256:
  `5cae0ca5f5978874f7c4e5da877d8396eb8e5abe33497bc766fd2b9354565df5`.
  Previous binary preserved at `/tmp/appcenter-before-normal-update.Y1FQCO`.
  Administrator authorization was used only to replace the App Center executable,
  after the unprivileged Firefox update had already completed successfully.

Preserved test releases: `/home/mai/appcenter-update-fixtures/20260923` on the VM.
Both generations of each app/runtime are also backed up as `.flatpak` bundles.
The isolated installation is reset to v1. See `README.md` for repeatable commands.
