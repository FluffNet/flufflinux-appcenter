# Mouse controls validation — 2026-09-26

Environment: Fluff Linux KDE/Wayland VM, Qt 6.11.2, KDE desktop controls.

## Behavior

- Mouse Back follows the existing page stack, including nested Queue → app
  navigation. At the root it does nothing. Open dialogs/menus prevent navigation
  behind them; informational tooltips do not block navigation.
- Middle-click starts anchored autoscroll with a dead zone and bounded speed.
  Middle-click again, left/right click, Escape or the wheel stops it. Holding the
  middle button and moving scrolls until release. Hiding/leaving the view, losing
  window activation or opening a popup also stops it.
- The stopping click never invokes an underlying button. Existing left-click,
  keyboard focus, wheel and touchpad handling is preserved.
- ScrollView/Pane-based pages catch middle clicks above their content because
  KDE panes otherwise swallow unused buttons. App details leaves its catcher
  below content so the nested horizontal screenshot strip can handle them first.

## Native integration

`tests/integration/MouseControlsSmoke.qml` passed in the real KDE/Wayland window.
It checks catalogue scrolling without opening a card, restoration of the previous
scroll offset (within one logical pixel), app details, Settings, Queue, Installed,
App Updates, and independent permissions-dialog scrolling. Escape stops dialog
scrolling without closing the dialog; Back cannot navigate behind it.

The autoscroll screenshot was visually inspected. Data and transactions are fake;
the fixture asserts the real backend stays idle. No Flatpak apps, source settings,
update history or desktop preferences were modified by these checks.

The native pointer-gesture regression passed all 8 checks, including existing
touchpad and image-preview interactions.

## Regression checks

At each of 100% and 150% scaling: Middle Scroll 10, Mouse Navigation 8, Wheel
Scroll 6, Catalogue Navigation 8, App Page 23, Permissions 11, Focus 90, Updates
43, Downloads Page 18, Sources 32, and Transactions 43 passed. Total: **584
QML checks, zero failures**. Expected offscreen missing icon-provider warnings
are unrelated to input; no type/reference errors or binding loops occurred.

## Deployment

Installed the six changed/new QML components and restarted App Center. The live
service is active, and installed files match the tested files byte-for-byte.
Existing five components are backed up on the VM at
`/tmp/appcenter-before-mouse-controls.lV99s7`; `MiddleMouseScroll.qml` is new.
The application executable, exclusions file and authorization policy are unchanged.
