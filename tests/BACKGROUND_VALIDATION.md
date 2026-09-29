# Background queue validation - 2026-09-27

Tested on the Fluff Linux KDE 6 Wayland VM. Public version remains
`2026.09 (Beta)`; pacman package revision is `2026.9.0beta-7`.

## Action labels and extending a running queue

- Queue cards now show `Action: Install` or `Action: Update` under the publisher,
  including queued, running, completed and failed entries. Removals remain
  outside Queue and its badge, as requested.
- Native manager/KDE tracker regression tests verify Installing, Updating and
  Removing titles. While app 2 runs, adding app 6 updates the original native
  notification from `2/5` to `2/6`, without creating another notification or
  restarting the job. Clearing history preserves that count; cancelling a
  queued entry reduces the denominator.
- The QML regression verifies that the same card survives `2/5` to `2/6`, its
  transfer measurements remain unchanged, and the sixth queued card is added.
  Icon alignment now checks the complete title/publisher/action text group.
- A real isolated `--append` run started five Flatpak installations, reopened
  App Center during app 2, added app 6, then closed App Center again. Actual
  screenshots show `App 2/6` in Queue and `Installing 2/6: Test App 2` in KDE.
  All six installed successfully, one numbered six-app summary appeared, and
  the sleep inhibitor was released. Regular Flatpak installations were untouched.
- The live fixture is retained at
  `/home/mai/appcenter-capture.8BaprY/appcenter-background-live-7sqgtetn`.
- Final regression: 24 QML suites / 655 cases passed with zero failures, including
  all eight install/update action-state combinations. The native background
  suite, 26 Rust application tests, 2 source-style tests and package archive
  validation also passed.
- Revision 7 was installed and reopened through the normal user service.
  Package integrity reports 82 files with zero altered files. The exclusions
  checksum and four regular Flatpak installations remain unchanged.

## Average speed, filter contrast and text follow-up

- Fixed the native job's missing elapsed timer. It starts with the actual
  operation, before the window closes, and survives reopening/closing the UI.
  Only the notification is detached while the window is visible.
- Native regression tests assert positive elapsed time and continuity across
  reopening, in addition to the existing cancellation and queue tests below.
- A real expanded KDE notification showed current speed 798.8 KiB/s and
  average speed 795.0 KiB/s during an isolated transfer. The five-app run
  completed successfully and released its sleep inhibitor.
- Fixed light-theme popup text disappearing on hover by using matching themed
  foreground and hover colors. Tests exercise every option in Installed,
  catalog sorting and category filters, with mouse and keyboard, in both themes.
  Pixel checks verify that the hovered text is actually painted and readable.
- All authored typographic dashes were replaced with ASCII hyphens, including
  comments, documentation and test fixtures. A Rust source-tree guard now runs
  during package checks to reject non-ASCII dashes.
- Completion summaries use numbered lines, such as `1. App name - Installed`.
  Native tests check numbering, exact separators and escaped app names.
- The real `--reopen` fixture restored all five entries while app 2 was
  downloading, with three still queued and the original job identity unchanged.
  Screenshots confirmed no native progress notification while open and its
  return after closing again. The expanded average remained 795.5 KiB/s.
  All five apps then completed with one numbered, ASCII-hyphen summary.
- Final checks: 24 QML suites / 646 cases, 26 Rust application tests plus
  2 source-style tests, native queue tests and real isolated update integration
  passed. The installed package has 82 files with zero altered files; the
  exclusions checksum and four regular Flatpak installations are unchanged.
- Temporary storage reached its quota during a screenshot retry. Subsequent
  live fixtures and package checks used a fresh folder on the VM's main disk;
  this was a test-harness storage issue, not an App Center transaction failure.

## Behavior

- The installed executable starts an on-demand, unprivileged systemd user
  service. No login autostart, root daemon, periodic scan or automatic update
  check was added.
- Closing the window leaves pending work alive. Reopening attaches to the same
  manager/queue; minimizing alone does not enable background notifications.
- While closed, native KDE job views report the same progress and transfer
  measurements as the in-app queue, with cancellation and completion messages.
  Queued jobs are not advertised as active downloads. An App Center tray action
  reopens the window, including any outstanding confirmation.
- Reopening removes notification proxies without cancelling the real work or
  emitting a false success. Hidden confirmations are never auto-approved.
- Multi-app jobs display their batch position (for example, `2/5`) alongside
  individual progress, both inside App Center and in the native notification.
  Completed history from previous batches is excluded; clearing finished history
  preserves the current position, and cancelling queued work adjusts the total.
- Multi-app completion is one native notification listing each app's outcome,
  including failures and cancellations. Intermediate completion popups are
  suppressed. An open-window completion does not send a background summary.
- KDE's suspend inhibitor is requested for installs, updates and confirmed
  removals, then released on completion, failure or cancellation. KDE's own
  short activation grace period and user overrides remain in force. Display
  blanking and screen locking are not inhibited.
- The closed, idle service exits after two seconds. Logout/reboot/crash recovery
  and persistent replay of interrupted transactions are outside this change.

## Automated results

- Rust release tests: **26 passed**, zero failures.
- QML regression: **24 suites, 640 passed**, zero failures.
- Native background tests passed: real manager/controller and KDE job tracker
  against isolated worker, notification and power-service fixtures. Covers
  close/reopen/minimize, queued vs running jobs, byte/percentage reporting,
  success, failure, cancellation acknowledgment, worker crash, hidden removal
  confirmation and suspend-inhibitor lifetime. An additional five-item batch
  verifies 2/5, clearing history, cancellation accounting and fresh-batch reset.
  Summary checks cover mixed outcomes, once-only reporting, escaped app names,
  and suppression while open (including closing after completion).
- CLI integration and isolated real Flatpak update integration passed.
- Package inspection passed: dependencies, static user service, Discover
  executable/desktop/icon aliases, conflicts/replacements and config backup.
- Installed package integrity: **82 files, zero altered files**.

## Live transactions and screenshots

`background_live.py` creates a new isolated Flatpak user installation with a
minimal runtime and a real 32 MiB test application. A localhost-only repository
is rate-limited to make the genuine transfer observable. No progress is invented.
The fixture closes App Center after transfer starts and confirms the actual app
is installed afterward. Regular user/system Flatpaks are not modified.

- Normal closed-window install succeeded, with KDE progress and completion
  screenshots; the PowerDevil inhibition was present during transfer and absent
  after completion.
- Fullscreen install succeeded. KDE reported `Notifications.Inhibited=true` and
  screenshots show the fullscreen test window without a progress or completion
  popup over it. The transaction still finished, and its inhibitor was released.
- An additional normal run captured progress/completion after temporarily using
  KDE's Show Desktop action; the previous desktop state was restored afterward.
- A five-app real transaction run also passed. Its screenshot shows
  `Installing 2/5: Test App 2` with actual bytes/speed/progress. All five apps
  completed in the isolated installation, and the sleep inhibitor was released.
- The final five-app summary run passed and captured one KDE notification with
  all five names and their Installed results, without stacked per-app popups.
- The five-app fullscreen summary run also passed: KDE suppression remained
  active, no completion summary appeared over the fullscreen test window, and
  the real installation and inhibitor release completed normally.
- Early harness attempts exposed PowerDevil's delayed activation and QML timers
  pausing with all windows hidden. The harness now waits for the KDE grace period
  and observes the real manager's completion signal. Failed harness-run notices
  were dismissed; they were not production transaction regressions.

Successful VM fixtures are retained for inspection/reuse:

- `/tmp/appcenter-background-live-vjqa7bv9` - normal install.
- `/tmp/appcenter-background-live-lrvu8v72` - fullscreen install.
- `/tmp/appcenter-background-live-t8h0ldpa` - final progress/completion captures.
- `/tmp/appcenter-background-live-sbdpfcyn` - five-app queue, 2/5 and completion.
- `/tmp/appcenter-background-live-wf3kqyhr` - final five-app summary list.
- `/tmp/appcenter-background-live-fu62cb_w` - five-app fullscreen summary test.

## Installed service/legacy launch verification

The installed `flufflinux-appcenter --updates` client exited successfully while
the user service continued running. `plasma-discover telegram` reused the same
service PID and displayed Telegram search results. Closing that verified idle
window resulted in `inactive`, `MainPID=0`, `Result=success`; a subsequent legacy
launch started a fresh service. The window retained the `org.kde.discover`
desktop identity for existing taskbar pins. No App Center tray item remained
while its window was open.

The package upgrade preserved the exclusions configuration. The original four
regular Flatpak applications remained installed in their original user/system
installations. Test installations, logs and screenshots are isolated from them.
