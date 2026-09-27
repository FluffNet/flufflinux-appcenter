# KDE app menu and add-ons validation

Validated on the Fluff Linux KDE 6/Wayland VM on 2026-09-27.
Public version remains `2026.09 (Beta)`; installed package is
`flufflinux-appcenter 2026.9.0beta-8`.

## Implemented behavior

- KDE's existing `Uninstall or Manage Add-Ons...` action opens App Center through
  its registered AppStream URL handler. Opening the page never uninstalls an app.
- Desktop launchers lowercase URL authorities. A unique case-insensitive fallback
  now resolves those IDs after exact matching; ambiguous IDs remain rejected.
- AppStream add-on components extend a parent app and are attached to that source,
  not listed as standalone applications in the catalog.
- An Add-Ons button appears beside Permissions when add-on metadata is present.
  Before parent installation the dialog is a read-only preview.
- For installed apps, libflatpak resolves compatible add-ons for the exact parent
  deployment, origin, architecture and extension branch. Install/remove actions
  are validated again in the worker, including the unchanged parent commit.
- Add-ons retain the parent's user/system scope. System changes still use
  Flatpak's existing authorization rules, not a new privileged service.
- Installs use the existing queue/progress/background support. Queue details open
  the parent app. Removals require confirmation, remain outside Queue, and do not
  close the parent or delete sandbox data.
- The dialog follows the app's scrollbar, button and light/dark theme styling.

## Checks and results

- Release build and package checks: 27 Rust tests and 2 source-style tests passed.
- Full QML regression suite: 665 checks passed, zero failures. This includes 9
  add-on checks and 28 Queue page checks. Coverage includes conditional button
  visibility, button placement, install/remove/cancel, failed read/retry, narrow
  long-text layouts, icon contrast, metadata refresh, and parent-page links.
- Native application-link tests passed: exact and lowercased IDs, desktop
  suffixes, installed-only apps, delayed installed-list loading, collisions,
  malformed/unknown URLs, and no unintended transactions/update checks.
- Native background queue regression passed: close/reopen, progress, continuous
  average speed, append/count accounting, success/failure/cancel/crash, hidden
  removal review, sleep inhibition and completion summaries.
- Real isolated Flatpak test passed: a parent app and two extension branches,
  compatible branch selection, rejection of a substituted runtime/ref/branch/
  installation and stale parent, real install, declined removal, confirmed
  removal, and preservation of the parent commit and base runtime.
- The live production dialog completed real install/remove operations against
  that isolated fixture, kept the dialog open after metadata refresh, checked
  the parent-safe confirmation, and verified removals stayed outside Queue.
- Actual KDE launcher test: searched for AnyDesk, opened its right-click menu,
  chose `Uninstall or Manage Add-Ons...`, and verified App Center opened the
  installed AnyDesk page with Open/Uninstall actions. No AnyDesk transaction ran.
- Final archive passed package identity/dependency/conflict/replacement, desktop
  handler, executable/icon aliases and config-preservation checks.
- After installation: `pacman -Qkk` reported 83 files, zero altered files. Regular
  Flatpak apps remained AnyDesk, Steam, Flatpak Builder and Firefox. The exclusions
  file checksum was unchanged.

The initial screenshot harness targeted a non-QML window item and was corrected
to capture the actual page/dialog items. A later live check caught overly broad
dialog closing on parent metadata refresh; this was fixed and regression-tested
before the final package was installed.

## Scope and limitations

This manages Flatpak apps and published Flatpak add-ons, not pacman packages,
browser extensions or plugins absent from AppStream metadata. Actual install/
remove testing used an isolated user installation. System-scope resolution and
validation are implemented, but a real system add-on transaction was not run.
The regular installed applications were not changed during this feature test.

## Captures and artifact

Real captures, not mockups, are retained under `output/addons/` in the working
tree. Add-on screenshots use an explicitly labeled isolated test app:

- `kde-menu.png`: AnyDesk's real KDE context menu.
- `kde-result.png`: installed App Center opened from that action.
- `appcenter-addons-button.png`: Add-Ons beside Permissions.
- `appcenter-addons-dialog.png`: compatible add-on with Install action.
- `appcenter-addons-installed.png`: installed add-on in dark theme.
- `appcenter-addons-light.png`: installed add-on in light theme.

Final package SHA-256:
`712e67100b9153e6b298846e453cc3e237989743b62eb495bfc78f60e06144ae`

Exclusions SHA-256 before and after:
`ffb8212a6bb802afaf89980ff6d7e9cd7593d24af9f7242ab18c284b6731bbd9`
