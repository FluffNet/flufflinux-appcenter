# Startup and background cache validation

Verified on the KDE Wayland test VM on 2026-09-28. The installed
`flufflinux-appcenter 2026.9b-1` package was tested but not replaced. All modified
code ran from a separate source checkout. Transaction tests used disposable
Flatpak installations, sources, config, cache and single-instance sockets.

## Installed build: 20 close/reopen cycles

`test_startup_cycles.py` uses the installed backend and installed Main.qml with
the actual 3,309-app catalog. Each close goes through the normal window-close
handler. Ten cycles start a new process; ten reopen before its idle exit.

| Path | Cycles | Minimum | Median | Maximum |
| --- | --- | --- | --- | --- |
| New process, fresh cache | 10 | 1.493 s | 1.515 s | 1.535 s |
| Reopen the still-live process | 10 | 0.081 s | 0.085 s | 0.088 s |

Every first frame contained the cached list, without catalog loading. None of
the new-process cycles refreshed sources. An ordinary installed launch outside
the timing fixture reported its cached catalog ready at 344 ms and first frame
at 1,505 ms. Process reuse explains one source of normal timing variation.

## Reproduced post-queue regression

`test_catalog_queue_reopen.py` first warmed a cache, set its source-refresh age
to one hour, then installed two tiny local Flatpaks and closed the window during
the queue. The local post-transaction catalog worker was paused for four seconds.

The installed build exited before that worker saved the changed installation
state. Reopening showed an empty, loading first frame and refreshed sources
despite the cache being younger than 12 hours. The installed VM journal also
showed an immediate Flathub/Flathub-beta refresh after the reported mixed queue.

There were two lifetime paths to fix: the idle timer did not count catalog work,
and releasing the final native KDE notification job's quit lock could exit the
hidden application independently of that timer. The controller now owns the
service lifetime and waits for actual worker completion.

## Fixed build

- The paused post-queue worker completed before idle shutdown. Reopening used
  the saved list and retained the original source-refresh timestamp.
- With `--reopen-during-save`, reopening while the worker was still paused took
  0.109 s. The original process showed its existing list with no empty/loading
  message. Closing it again still allowed the same save to finish. A subsequent
  fresh-process launch used that cache.
- The worker has one 30-second deadline for local parsing, writing and
  unstable-input retries. Reopening/closing does not reset it. Native tests use
  a shortened deadline to prove stuck work stops and preserves the previous file.
  Once no work remains, the existing two-second idle shutdown delay applies.
- Disk writes run in the catalog child process, not on the GUI thread. Atomic
  replacement explicitly forbids direct-write fallback. A killed partial writer
  and an unwritable cache directory both left the previous good cache intact.
- SHA-256 validation rejects altered but syntactically valid JSON. Truncated,
  oversized, invalid and future-dated snapshots are rejected too.
- The real HTTP-source test verified zero source requests/rebuilds under 12
  hours, and an empty loading view followed by newly published source metadata
  after expiry. The new cache's timestamp renewed only after the actual refresh.
- Native source tests retain offline deferral, LAN/limited attempts, all-source
  failure handling and unchanged age for local-only rebuilds.
- Loading, empty and central error messages use bold theme-foreground text.
  Catalog loading reads `Loading...`, and `No results.` follows the same style.
  Dark/light tests cover those labels, network notices and App Updates states.

Changing the binary or cache format invalidates an old snapshot intentionally.
The first launch after installing this fix may refresh once; subsequent launches
reuse the new snapshot for its remaining 12-hour lifetime.

## Regression commands

Run on Linux from the source checkout:

```sh
cargo test
sh tests/run_catalog_availability.sh
sh tests/run_background.sh
sh tests/run_qml_suite.sh
```

Run inside the KDE session, against the built binary:

```sh
python3 tests/integration/test_catalog_startup.py target/release/flufflinux-appcenter
python3 tests/integration/test_catalog_queue_reopen.py target/release/flufflinux-appcenter --reopen-during-save
python3 tests/integration/test_startup_cycles.py /usr/bin/flufflinux-appcenter
```

The queue test installs only its isolated fixtures, which are removed with its
temporary directory. It does not change the user's installed Flatpaks or sources.

## Overall loading percentage and clean Flathub pulls

The loading label now reads only `Loading... 50%`, centered in bold theme
foreground. There is no additional heading, progress bar or stage description.
Progress is weighted completed work rather than a time estimate: setup 0-10%,
source refreshes 10-70%, parsing 70-95%, serialization/save 96-99%, and 100%
only after the manager has accepted the result. Worker callbacks drive updates;
there is no timer that advances progress while work is stalled.

On 2026-09-28, `test_catalog_progress_live.py` ran two real Flathub pulls, each
with new empty user/system Flatpak installations and isolated config/cache.
App Center itself added Flathub inside the measured interval. No existing
AppStream or app-list cache was available. Each cold run was followed by a
fresh-process warm launch with the same profile.

| Run | First cold window | Cold list ready | Cached list ready |
| --- | --- | --- | --- |
| 1, dark theme | 0.444 s | 42.683 s | 1.464 s |
| 2, light theme | 0.592 s | 36.940 s | 1.700 s |

Both runs displayed 3,298 real applications. Source setup/refresh reached its
completion milestone at 34.862 s and 29.019 s respectively. The percentage
advanced monotonically through source, parser and save work. Neither cached
launch displayed the loading text, rebuilt the list, or rewrote its cache.
The run-to-run difference is not evidence of a theme performance difference.

The existing KDE/Wayland VM has about 8 GiB RAM. Only the test processes were
restricted to two CPUs; the VM and other processes were not reconfigured.
Captures use the software Qt Quick renderer and the production UI/backend.
This recreates empty application/source caches, not a freshly booted OS with
all kernel, DNS and server-side caches cleared. Live network times will vary.
Real screenshots, complete logs and timing JSON are in `output/loading-progress/`.
The installed package, normal user cache, sources, apps and theme were untouched.

Verification includes 675 passing QML checks, 28 Rust tests, two source-text
guards, and native source/cache/manager checks. Progress tests cover split IPC
messages, backwards/malformed reports, parser retries, failure below 100%, and
fresh-cache loading-screen suppression. The existing 12-hour HTTP-source test
also verifies that expiry still downloads genuinely changed metadata.
