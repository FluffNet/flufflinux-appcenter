# Network availability validation — 2026-09-24

Tested on the KDE 6 Wayland VM, Qt 6.11.2, at 100% and 150% scaling.

## Status policy

- NetworkManager disabled/asleep (10) or disconnected (20), including no
  interfaces: Home/categories/search show No Network Connection; Updates is
  disabled and dimmed. Installed and its local search remain usable.
- Connected locally (50), even with Connectivity=NONE: LAN-only note; actions
  remain enabled. Connected site-wide (60) or limited (Connectivity=3): limited
  note; actions remain enabled. Captive portals show a sign-in note, not a lockout.
- Connecting/disconnecting: transient advisory, no hard lockout. Unknown, missing,
  malformed or unavailable NM status: do not infer that the machine is offline.
- Online/reconnected: restore the catalog and actions without checking updates.

The production observer reads properties asynchronously, subscribes to property
changes and daemon-owner changes, bounds calls to 2.5 seconds, and ignores stale
responses. No CheckConnectivity, network mutation, system service installation,
authorization request, polling or daemon autostart is involved.

## Automated checks

- Native policy and private-D-Bus tests passed: disconnected/no-interface,
  LAN-only with every connectivity value, limited, portal, connecting, online,
  unknown/malformed states, live changes and invalidations, failed/timed-out
  replies, stale replies and daemon restart. The fake NM rejects any method other
  than read-only GetAll. A separate read of the real system bus reported online.
- New QML suite: 39 passed at each of 100% and 150% scaling. Covers every catalog
  category, disabled mouse/programmatic Updates entry, KDE icon identity, offline
  search/Installed behavior, all allowed states, manual check and update actions,
  connection loss while Updates is open, preserving selections, cancellation,
  reconnect without checking, pending startup status, and narrow/short note fit
  with and without an active Queue button.
- Full 21-suite QML regression passed at 150% scaling. The graphics-heavy hover
  suite exhausted VM memory when run in one process; all its cases passed in
  three isolated groups (54, 46 and 8, each including setup/cleanup). No assertions
  were removed. The other 20 suites reported 463 passes, with no failures, followed
  by eight additional Queue/note-layout cases in the focused network suite.
- Rust: 16 passed. Optimized Linux build passed.

## Real KDE screenshots

`tests/integration/NetworkSmoke.qml` renders the real app and catalog while
injecting simulated connection states, without changing the VM's networking.
Eight screenshots were captured and visually inspected at 150%:

1. Offline Home, with disabled Updates and catalog search.
2. Offline Internet category, using the same full-page warning.
3. LAN-only Home, with an advisory and usable catalog/Updates.
4. Limited Home, with an advisory and usable catalog/Updates.
5. Captive-portal Home, with the sign-in advisory.
6. Limited Updates, with Check for Updates enabled.
7. Connection lost while Updates is open, with checking disabled.
8. Online Home, with no warning and normal controls restored.

The native fixture asserted update state remained idle throughout. The warning
is KDE's `dialog-warning` icon in the current theme, not an emoji or custom glyph.
No QML binding/type errors occurred in the successful run. Existing locale and
Mesa software-renderer warnings are unrelated to these changes.

No regular Flatpak app was installed, updated or removed, and no network
connection was disconnected. The existing exclusion configuration was preserved.
