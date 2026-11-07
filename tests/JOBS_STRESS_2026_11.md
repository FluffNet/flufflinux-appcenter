# Update and removal stress verification - 2026-11-06

Tested on the Fluff development VM with Qt 6.12.0, Flatpak 1.18.4 and the
2026.11-1 draft. Real transactions used temporary installations, source
repositories, settings and HOME directories. Desktop apps and sources were
not changed by these tests. Native worker fixtures are identified below.

## Failure found and corrected

Repeated native cache-expiry runs exposed a race at the six-hour boundary.
Qt's coarse timer can fire early. When less than one millisecond remained,
integer truncation turned that positive duration into zero and selected the
15-minute failed-refresh backoff. This could postpone a refresh after the
queue became idle.

The scheduler now preserves positive sub-millisecond durations and rearms
for at least one millisecond. An explicit 500-microsecond boundary regression
passes, followed by 20 consecutive native expiry runs with 200 queued jobs,
idle-only refresh, atomic replacement, failed refresh and targeted Retry.

## Real transactions

`test_mixed_jobs_stress.py` passed in English, Hebrew RTL and German. Each run
used 24 installed test apps and performed:

- Eleven app updates plus their shared runtime update.
- Cancellation of one queued update, with its original commit preserved.
- Twelve independent removal prompts: nine approved and three declined.
- Update/removal worker overlap and navigation between Updates and Queue.
- Rejection of an attempted uninstall of an app already being updated.
- Rejection of stale approval tokens for a different removal prompt.
- Verification of every final app commit and each app-data marker.
- A separate symlinked parent data-directory case: explicit cleanup failure,
  with the protected target and original data preserved.

No unrelated source or system installation changed. The real update,
solver cleanup/rebase, retry and add-on suites also passed. Those cover
in-use/pinned runtime protection, replacement failure and retry, HTTP
503/404 recovery, bounded retry exhaustion, cancellation during backoff,
HTTP 403, corrupt payload rejection and declined/confirmed add-on removal.

## Native lifecycle and queue tests

The parallel-worker, removed-history, cancellation, update-manager and
background-queue tests each passed three times. Their workers are simulated,
but the Rust manager, Qt transport, review tokens, timers and process
watchdogs are real. Coverage includes stubborn worker termination, late
progress, cancellation from a signal handler, preserved live indices after
history clearing, worker failure/crash, close/reopen/minimize and shutdown.

A three-batch soak completed 600 simulated updates in one process while
scrolling Updates/Queue, retaining completed history, clearing history and
idling between batches. It ran for 321 seconds. A separate 200-row QML test
passed 1,000 progress replacements, scrolling between both ends, virtualized
offscreen delegates and repeated page reopen. Its longest measured event-loop
heartbeat gap was 46 ms.

## Memory and timing observations

The 600-update soak measured:

| Measurement | KiB | MiB |
| --- | ---: | ---: |
| GUI high-water RSS | 165956 | 162.07 |
| Sampled combined process-tree RSS peak | 393744 | 384.52 |
| Sampled combined process-tree PSS peak | 177910 | 173.74 |
| GUI RSS near idle after batch 1 | 162844 | 159.03 |
| GUI RSS near idle after batch 2 | 164448 | 160.59 |
| GUI RSS near idle after batch 3 | 165756 | 161.87 |

The configured 1,000,000,000-byte guard did not trigger. RSS sums count shared
pages repeatedly; PSS apportions them. Process-tree samples are not atomic.
The fixture retains timing samples, and the small per-cycle RSS increase has
not been attributed solely to application allocations. This does not prove
the absence of a slow leak or a universal limit for full Flathub catalogs.

The real mixed-job runs sampled GUI peaks of 144568-145320 KiB and process-tree
peaks of 249172-276056 KiB. Their longest heartbeat gaps were 106-117 ms.
The soak's overall heartbeat p99 was 41 ms and maximum was 112 ms; its
software-rendered frame maximum was 271 ms. These are headless synthetic
results collected while other isolated tests also ran, not a physical-device
scrolling or touchpad-feel assessment.

## Regression checks and reproduction

- 155 Rust tests passed; one pre-existing opt-in test remained ignored.
- Strict Clippy with warnings denied passed.
- 251 QML checks passed across transactions, Updates, Queue, recovery, RTL,
  long translated labels and queue stress.
- All 20 repeated native expiry checks passed after the timer correction.

Run `sh tests/run_jobs_stress.sh` from the repository root on a development
system with the existing build/test prerequisites. It builds feature variants
sequentially, runs isolated real transactions and native fixtures, then the
memory soak and QML checks. Logs are written to `target/jobs-stress/`.

Passing these cases is evidence for the tested behavior, not a guarantee that
every possible update, removal, operating-system or network failure is covered.

## Follow-up: immediate size estimates after removal

Removal now publishes a loading estimate with the installed-state change and
immediately starts the visible app's bounded size worker, before scheduling
another queued transaction. It does not wait for the queue to drain or rebuild
the catalog first. A replaced size worker cannot overwrite the new estimate.
An initial missing result also displays the existing translated `Loading...`
text; `Unavailable` remains reserved for an unsuccessful lookup or a genuinely
unknown field in a completed partial result.

The expanded real size-lifecycle test passed in English, Hebrew RTL and German.
Each session performed ten cycles installing and removing two temporary apps
(60 installs and 60 removals across all three sessions). During each cycle,
the second removal was deliberately kept queued until the first app's reinstall
estimate arrived. Both size labels updated without reopening the page, and
the estimates were observed ready within about 210 ms at worst on this VM.
The same test verifies summary-cache eviction/recovery, metadata-only fetching,
warm reuse, runtime-aware totals, disabled/mismatched sources and offline failure.

All three real mixed update/removal suites passed with additional checks that
the reinstall estimate resolves while updates are still active. No false
unavailable state was observed during concurrent removal. The existing
approval, cancellation, data-preservation and final-commit checks also passed.
Sampled GUI peaks were 143672-144500 KiB; sampled combined process-tree peaks
were 303152-327920 KiB. These are samples from temporary fixtures, not a
universal memory or latency guarantee.

The follow-up passed 156 Rust tests (one existing opt-in test ignored), strict
Clippy, the release build, and 146 QML checks covering transactions, RTL and
long labels. The stress runner now includes the expanded size-lifecycle test
for all three locales.
