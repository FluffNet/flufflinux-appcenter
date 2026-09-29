#!/usr/bin/env python3
"""Opt-in KDE desktop activation using real files, but no approved installs.

Run inside the VM's graphical user session after installing the tested package.
Provide a downloaded HandBrake .flatpakref and a genuine local .flatpak bundle.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

assert os.environ.get("APPCENTER_DESKTOP_TESTS") == "1"
assert os.geteuid() != 0
reference, bundle = (Path(value).resolve(strict=True) for value in sys.argv[1:])
repo = Path(__file__).resolve().parents[2]
captures = repo / "target/desktop-verification"
captures.mkdir(parents=True, exist_ok=True)
before = subprocess.check_output(["flatpak", "list", "--columns=ref,installation"], text=True)
assert "org.gimp.GIMP/" in before and "fr.handbrake.ghb/" not in before
with tempfile.TemporaryDirectory(prefix="appcenter-desktop-live-") as temporary:
    root = Path(temporary)
    root.chmod(0o700)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(root), XDG_CONFIG_HOME=str(root / "config"),
               XDG_CACHE_HOME=str(root / "cache"), WAYLAND_DISPLAY="/run/user/1000/wayland-0",
               FLUFF_APP_CENTER_QML=str(repo / "tests/integration/DesktopOpenLive.qml"),
               QT_FORCE_STDERR_LOGGING="1")
    log = captures / "live.log"
    def wait_for(marker, offset=0, timeout=75):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            text = log.read_text()[offset:]
            assert "DESKTOP_ERROR" not in text and "DESKTOP_CAPTURE_FAILED" not in text, text
            if marker in text: return text
            assert first.poll() is None, log.read_text()
            time.sleep(0.1)
        raise AssertionError(log.read_text()[offset:])
    def open_desktop(value):
        offset = len(log.read_text())
        subprocess.run(["gio", "open", str(value)], env=env, check=True, timeout=30)
        return offset
    def last_state():
        return json.loads([line.split("DESKTOP_STATE ", 1)[1] for line in log.read_text().splitlines()
                           if "DESKTOP_STATE " in line][-1])
    with log.open("w") as stream:
        first = subprocess.Popen(["/usr/bin/flufflinux-appcenter", "--search", "initial search"],
                                 env=env, stdout=stream, stderr=stream)
        try:
            wait_for("DESKTOP_STATE")
            for count, link in enumerate(("appstream://org.invalid.DoesNotExist",
                                          "appstream://fr.handbrake.ghb",
                                          "appstream://org.kde.gwenview.desktop"), 1):
                offset = open_desktop(link)
                wait_for("DESKTOP_CAPTURE home-fallback-" + str(count), offset)
                state = last_state()
                assert state["depth"] == 1 and state["category"] == "All Apps" and state["search"] == "", state
                assert not state["jobs"], state
            offset = open_desktop("appstream://org.gimp.gimp")
            wait_for("DESKTOP_CAPTURE app-org.gimp.GIMP", offset)
            assert last_state()["uninstall"] and not last_state()["install"], last_state()
            offset = open_desktop(reference)
            wait_for("DESKTOP_CAPTURE app-fr.handbrake.ghb", offset)
            assert last_state()["install"] and not last_state()["uninstall"], last_state()
            offset = open_desktop(bundle)
            wait_for("DESKTOP_CAPTURE local-bundle-confirmation", offset)
            wait_for('"busy":false', offset)
        finally:
            first.terminate()
            first.wait(timeout=15)
after = subprocess.check_output(["flatpak", "list", "--columns=ref,installation"], text=True)
assert before == after, "Desktop opening must not install, update or remove any application"
print("PASS: real desktop defaults, unknown/uninstalled/system app Home fallback, installed GIMP, downloaded HandBrake reference, local bundle confirmation; installed refs unchanged")
print("Screenshots:", captures)
