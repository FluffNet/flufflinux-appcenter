# Mouse controls validation — 2026-09-26–27

Environment: Fluff Linux KDE/Wayland VM, Qt 6.11.2, KDE desktop controls.

## Zoomed screenshot drag isolation — 2026-09-27

- Reproduced the actual background-grab failure using timestamped mouse events
  after a timed page drag. The picture starts panning, loses its active handler,
  then the background scrolls while the modal viewer stays visible. The original
  zero-timestamp test events bypassed the timed grab path and missed this bug.
- The permanent regression fails on the original code: at 200% zoom the image
  loses the drag. Original-code checks also fail for existing page flicking,
  smooth wheel animation and thumbnail-strip flicking continuing behind it.
- The viewer now suspends the underlying page and thumbnail scroll inputs for
  its entire visible lifetime. Opening it cancels existing kinetic/smooth/middle
  scrolling before the opening animation, without resetting either position.
  Scrolling is restored after the viewer closes.
- Regression coverage includes 144 timed drags per run: normal/compact windows,
  125%/200%/400% zoom, center/edge starts, four directions, mouse and held-touchpad
  devices. Repeated clicks, release behavior, five background-motion scenarios
  and ordinary wheel scrolling after closing are checked separately.
- Fixed code: the full native gesture suite passed all 28 checks at 100% and
  150% offscreen scaling and again in KDE/Wayland (84 total; 432 matrix drags).
  App Page 23, Mouse Navigation 8, Middle Scroll 10, Wheel Scroll 6, Catalogue
  Navigation 8 and Focus 90 passed at each scale: 290 additional QML checks.
  No failures, type/reference errors or binding loops in the fixed-code runs.
- Installed only `AppPage.qml` and restarted the live app successfully. The
  installed file matches the tested version; the prior file is preserved at
  `/tmp/appcenter-before-preview-drag.RtooCw/AppPage.qml` on the VM. The executable,
  exclusions and authorization policy are unchanged; no Flatpak apps were changed.

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
