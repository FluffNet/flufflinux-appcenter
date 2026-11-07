# Complete-data update scan profiling

The update list still appears only after versions, download sizes, dependency
plans and permission comparisons have been prepared. No provisional rows or
new UI strings were introduced.

## 2026.11-2 checking indicator

The package candidate is now `2026.11-2`; the upstream application/Cargo
version remains `2026.11` / `2026.11.0`. The accepted `2026.11-1` Desktop
candidate and installed package are not replaced by these draft changes.

Checking shows a percentage, the current source or app, and the existing
activity spinner. The percentage describes completed scan stages, not network
bytes or an estimate of remaining time. Each installation reserves 25% for
source discovery, 20% for version metadata and 55% for planning/finalization.
A slow Flathub response holds the percentage steady while the source remains
visible. No timer invents progress. Source names and app identities remain
untranslated; captions reuse existing translations.

Worker progress is capped below 100 and the manager rejects regressions.
Only a finished result publishes 100 alongside the fully populated list.
Cancellation/error does not publish completion, and a new scan resets to zero.
The same progress bar mirrors its fill in RTL.

Live mixed-job testing also exposed brief contention between an update worker
and removal history writes. Transaction workers now retry only WouldBlock
history-lock errors for at most 500 ms; GUI history writes remain nonblocking
and permanent errors are still reported. A held-lock/two-writer regression
verifies eventual saving and preservation of both entries.

Validation after these additions: 159 Rust checks including translation and
launcher coverage passed, strict Clippy and release/fakeroot staging passed,
and 63 Updates QML checks passed. The real complete-row comparison checks
monotonic worker percentages in addition to unchanged plans/data. Nine live
mixed update/removal runs passed (three each in English, Hebrew RTL and
German), including progress reset and 100 only with complete results. Eighteen
native screenshots cover both palettes, source/planning states and narrow
long-label layouts. The narrow German heading can shrink further before
wrapping to avoid a single orphaned character.

Render those screenshots with:

```sh
python3 tests/integration/capture_update_check.py target/debug/flufflinux-appcenter
```

## Baseline findings

An instrumented scan of the development VM found 33 pending app/runtime
updates across user and system installations. It took 40.04 seconds:

| Stage | Seconds |
| --- | ---: |
| Remote-ref enumeration | 1.82 |
| AppStream refresh | 28.51 |
| Version lookup | 1.59 |
| Serial transaction planning | 7.97 |

Source verification took 0.43 seconds within those plans, not in addition to
them. Both installations used the same Flathub URL and trust settings, but
the baseline attempted two separate AppStream refreshes. The initial scan
included network/cache warming; it must not be compared directly with a warm
candidate scan to claim a speedup. These measurements are not from Harry's
computer and do not establish the exact cause of his two-minute wait.

## Changes

- Resolve at most two read-only plans concurrently, with a separate Flatpak
  handle and GLib context per thread. Results retain their original ordering.
- Within one scan, reuse successful version metadata only when the source URL
  and its complete trust/filter identity match. A shared remote name is not
  sufficient, and failed refreshes are not cached as successful results.
- Keep fresh per-installation commit discovery and current transaction
  validation. Scanning still stops before authorization/deployment.
- Add opt-in `APPCENTER_PROFILE_SCAN=1` stage timings on stderr. Normal worker
  output and translated UI messages are unchanged.

Version lookup retains its normal Flatpak behavior for both HTTP and
file-based sources, including complete version data.

## Controlled comparison and functional checks

The HTTP fixture serves temporary packages with 50 ms added latency per
metadata request. Every baseline/candidate run starts from an identical copy
of the installed commits, AppStream files and OSTree objects. It compares
complete rows exactly and verifies that neither scan deploys anything.

For 30 apps plus one shared runtime, the final three baseline runs were about
2.74 seconds each; candidate runs were about 1.81 seconds each, approximately
34% shorter. All 31 rows matched, including versions, sizes, source identities,
operation plans and changed/unchanged permissions. A second-origin case with
the same URL and different dependency policy also matched and independently
refreshed both sources.

The same comparison also passed with 200 apps plus one shared runtime. Three
baseline scans took 16.90, 16.36 and 16.22 seconds; candidate scans took 8.78,
8.59 and 8.68 seconds. The median time fell by about 47%, with all 201 complete
rows identical and all deployments unchanged. Both implementations made the
same 215 metadata requests; this test measures overlapping work rather than
skipping requests. Sampled worker RSS peaked at 52944 KiB for the baseline and
54600 KiB for the candidate. The additional distinct-source-policy run also
passed (16.36 versus 8.71 seconds, with two independent metadata refreshes).

The complete Rust suite passed 156 tests (one existing opt-in test ignored),
strict Clippy passed, and real isolated suites passed for update versions and
permissions, disabled/offline sources, cancellation, runtime cleanup, pinned
and in-use runtimes, rebases, stale plans, HTTP recovery and integrity failures.
Real mixed updates/removals passed in English, Hebrew RTL and German. Their
sampled GUI peaks were 143916-145456 KiB and combined process-tree peaks were
325528-327996 KiB. Timing and memory samples are specific to these fixtures;
they do not guarantee a universal latency, memory ceiling or physical-device
scrolling feel.

## Reproduction

Build a baseline executable from `ed77029` separately, then build this branch
with the existing build prerequisites. Run:

```sh
python3 tests/integration/test_scan_performance.py /path/to/baseline target/debug/flufflinux-appcenter
APPCENTER_SCAN_STRESS_ITEMS=200 python3 tests/integration/test_scan_performance.py /path/to/baseline target/debug/flufflinux-appcenter
```

Only temporary installations, sources and app data are modified. To inspect
stage timing on an existing installation without deploying updates:

```sh
APPCENTER_PROFILE_SCAN=1 target/debug/flufflinux-appcenter --updates-worker '{}'
```

This can refresh Flatpak metadata. Do not use the optional source-restoration
request when only profiling a read-only update check.
