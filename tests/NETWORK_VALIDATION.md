# Network availability validation — 2026-09-24

Tested on the KDE 6 Wayland VM, Qt 6.11.2, at 100% and 150% scaling.

## Status policy

- NetworkManager disabled/asleep (10) or disconnected (20), including no
  interfaces: Home/categories/search show No Network Connection; Updates is
  disabled and dimmed. Installed and its local search remain usable.
- Connected locally (50), even with Connectivity=NONE, connected site-wide (60),
  limited (Connectivity=3), captive portals, connecting/disconnecting: **no note**
  and no hard lockout. Source catalogs are allowed to load normally. Unknown, missing,
  malformed or unavailable NM status: do not infer that the machine is offline.
- Online/reconnected: restore the catalog and actions without checking updates.
- Every source failed with no usable catalog: Home/categories/search show
  Cannot Connect to Sources, the KDE warning triangle, connection advice and
  Try Again. This is based on worker catalog-load results, not NM connectivity.
- Partial success and usable cached catalogs remain browsable. A valid empty
  catalog, no configured/enabled sources and cancellation are not network errors.
  Source failures alone do not disable Updates. Try Again refreshes source
  catalogs; it never checks app updates. Settings retains per-source errors.

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
- Updated QML suite: 47 passed at each of 100% and 150% scaling. Covers every catalog
  category, disabled mouse/programmatic Updates entry, KDE icon identity, offline
  search/Installed behavior, all allowed states, manual check and update actions,
  connection loss while Updates is open, preserving selections, cancellation,
  reconnect without checking, pending startup status, narrow/short header fit
  with and without Queue, source failure in each allowed network state, retry,
  recovery, empty success and offline precedence. No connectivity notes remain.
- Focused seven-suite regression at 100%: 231 passed, zero failed (network,
  search input, source settings, Home, catalog navigation, Updates and focus).
- Native production manager test: all-failed, partial success, empty success,
  no sources, retry/loading, preservation across Settings and cached fallback.
- Real worker with isolated temporary Flatpak repositories: all failed, one
  cached/one failed, failed refresh with cache, disabled and removed sources,
  valid empty catalogs and fresh successful recovery from a local repository.
  No Internet access or app installation needed for these tests.
- Existing source integration tests passed with the rebuilt worker: user/system
  mirroring, disabled state, persistent removals, denied/cancelled authorization,
  untrusted source confirmation and system-before-user removal sequencing.
- Rust: 16 passed. Optimized Linux build passed.

## Real KDE screenshots

`tests/integration/NetworkSmoke.qml` renders the real app and catalog while
injecting simulated connection states, without changing the VM's networking.
Ten screenshots were captured at 150% (network states and aggregate source
failure are injected at the UI boundary; catalog, theme and rendering are real):

1. Offline Home, with disabled Updates and catalog search.
2. Offline Internet category, using the same full-page warning.
3. LAN-only Home: no note, usable catalog/Updates.
4. Limited Home: no note, usable catalog/Updates.
5. All sources failed on Home, with Try Again.
6. All sources failed in the Internet category, with Try Again.
7. Captive-portal Home: no advisory.
8. Limited Updates, with Check for Updates enabled.
9. Connection lost while Updates is open, with checking disabled.
10. Online Home, with normal controls restored.

The native fixture asserted update state remained idle throughout. The warning
is KDE's `dialog-warning` icon in the current theme, not an emoji or custom glyph.
No QML binding/type errors occurred in the successful run. Existing locale and
Mesa software-renderer warnings are unrelated to these changes.

No regular Flatpak app was installed, updated or removed, and no network
connection was disconnected. The existing exclusion configuration was preserved.
