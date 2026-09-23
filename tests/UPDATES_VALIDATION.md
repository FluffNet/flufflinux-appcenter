# Updates validation — 2026-09-23

Test environment: Fluff Linux KDE/Wayland VM, Flatpak 1.18.2, Qt 6.11.2.

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

The normal user/system scan found runtime updates, not app updates. Real system
deployment/Polkit interaction was not exercised; system/named update routing is
covered by simulations. No regular app or runtime was updated by these tests.
The final per-source scan reports Firefox/Flatpak Builder as skipped when their
system Flathub source cannot be restored, rather than silently calling them current.
No source was added, removed or reconfigured in the regular installations.

The opt-in real-desktop recovery test reached KDE's configure-remote authorization,
then safely timed out because authentication was not completed in the VM. Both
attempts preserved the missing source, skipped the system apps and retained only
healthy user-source candidates. A successful privileged restoration remains to
be verified after administrator authorization; the source-recovery build has not
yet replaced the installed build. The ordinary apps' commits and settings hash
were unchanged.

Read-only authorization checks against the running desktop App Center process:
`org.freedesktop.Flatpak.app-update` returned authorized (exit 0) without interaction;
`org.freedesktop.Flatpak.configure-remote` returned authentication required (exit 2).
The installed policy allows signed app updates in an active desktop session, but
source configuration requires administrator authentication. SSH/inactive sessions
are different. No authorization rules were changed.

Preserved test releases: `/home/mai/appcenter-update-fixtures/20260923` on the VM.
Both generations of each app/runtime are also backed up as `.flatpak` bundles.
The isolated installation is reset to v1. See `README.md` for repeatable commands.
