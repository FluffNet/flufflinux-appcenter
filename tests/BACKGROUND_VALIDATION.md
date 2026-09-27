# Background queue validation — 2026-09-27

Tested on the Fluff Linux KDE 6 Wayland VM. Public version remains
`2026.09 (Beta)`; pacman package revision is `2026.9.0beta-5`.

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
  confirmation and suspend-inhibitor lifetime.
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
- Early harness attempts exposed PowerDevil's delayed activation and QML timers
  pausing with all windows hidden. The harness now waits for the KDE grace period
  and observes the real manager's completion signal. Failed harness-run notices
  were dismissed; they were not production transaction regressions.

Successful VM fixtures are retained for inspection/reuse:

- `/tmp/appcenter-background-live-vjqa7bv9` — normal install.
- `/tmp/appcenter-background-live-lrvu8v72` — fullscreen install.
- `/tmp/appcenter-background-live-t8h0ldpa` — final progress/completion captures.

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
