#!/usr/bin/env python3
"""Run with dbus-run-session: exercise real app -> KDE -> XDG portal -> QML.

Mock only the portal's file chooser, not the app or Qt's platform integration.
No desktop input, real file chooser, repository changes, or app installations.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from gi.repository import Gio, GLib

ROOT = Path(__file__).resolve().parents[2]
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
name = "org.freedesktop.portal.Desktop"
reply = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                      "RequestName", GLib.Variant("(su)", (name, 4)), None,
                      Gio.DBusCallFlags.NONE, -1, None)
assert reply.unpack() == (1,), "Run on a fresh private bus; never replace the real desktop portal"
xml = """<node><interface name="org.freedesktop.portal.FileChooser">
<method name="OpenFile"><arg type="s" direction="in"/><arg type="s" direction="in"/>
<arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method>
<property name="version" type="u" access="read"/></interface></node>"""
calls = []
errors = []


def choose(connection, sender, path, interface, method, params, invocation):
    try:
        parent, title, options = params.unpack()
        assert method == "OpenFile" and title == "Choose a Flatpak repository"
        assert options["modal"] and not options["multiple"] and not options["directory"]
        assert any(pattern == "*.flatpakrepo" for _, filters in options["filters"] for _, pattern in filters)
        request = "/org/freedesktop/portal/desktop/request/" + sender[1:].replace(".", "_") + "/" + options["handle_token"]
        calls.append(options)
        invocation.return_value(GLib.Variant("(o)", (request,)))
        cancel = len(calls) == 2

        def respond():
            results = {} if cancel else {"uris": GLib.Variant("as", [selection.as_uri()])}
            connection.emit_signal(sender, request, "org.freedesktop.portal.Request", "Response",
                                   GLib.Variant("(ua{sv})", (1 if cancel else 0, results)))
            return GLib.SOURCE_REMOVE

        GLib.timeout_add(250, respond)
    except Exception as error:
        errors.append(str(error))
        invocation.return_dbus_error("org.freedesktop.portal.Error.Failed", str(error))


node = Gio.DBusNodeInfo.new_for_xml(xml)
bus.register_object("/org/freedesktop/portal/desktop", node.interfaces[0], choose,
                    lambda *args: GLib.Variant("u", 4), None)
with tempfile.TemporaryDirectory(prefix="appcenter-picker-") as temporary:
    selection = Path(temporary) / "source picker fixture.flatpakrepo"
    selection.write_text("[Flatpak Repo]\nTitle=Picker test only\n")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               QT_QPA_PLATFORMTHEME="kde", QT_QUICK_CONTROLS_STYLE="org.kde.desktop",
               XDG_RUNTIME_DIR=temporary, XDG_CONFIG_HOME=temporary + "/config",
               XDG_DATA_HOME=temporary + "/data", XDG_CACHE_HOME=temporary + "/cache",
               QT_LOGGING_RULES="*.info=true;*.warning=true;*.critical=true",
               FLUFF_APP_CENTER_QML=str(ROOT / "tests/integration/SourcePickerSmoke.qml"))
    env.pop("PLASMA_INTEGRATION_USE_PORTAL", None)  # Verify the production default.
    loop = GLib.MainLoop()
    with tempfile.TemporaryFile(mode="w+") as log:
        process = subprocess.Popen([str(Path(sys.argv[1]).resolve())], env=env, stdout=log, stderr=log)

        def poll():
            if process.poll() is None:
                return GLib.SOURCE_CONTINUE
            loop.quit()
            return GLib.SOURCE_REMOVE

        def timeout():
            errors.append("Portal test timed out")
            process.kill()
            return GLib.SOURCE_REMOVE

        GLib.timeout_add(100, poll)
        watchdog = GLib.timeout_add_seconds(25, timeout)
        loop.run()
        GLib.source_remove(watchdog)
        if process.returncode or errors or len(calls) != 2:
            print("Portal calls:", calls, "Errors:", errors)
            log.seek(0)
            print(log.read())
        assert process.returncode == 0, process.returncode
        assert not errors, errors
        assert len(calls) == 2, f"Expected accepted and cancelled portal requests, got {len(calls)}"
print("PASS: native XDG portal picker, repository filter, selection, cancellation, no source/Queue changes")
