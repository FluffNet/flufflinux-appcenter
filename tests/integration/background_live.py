#!/usr/bin/env python3
"""Opt-in real, rate-limited Flatpak installation with the App Center closed.

Uses a new isolated Flatpak installation and a localhost-only test repository.
Leaves the fixture, journal and actual KDE screenshots in the printed folder.
Run inside the KDE session (e.g. systemd-run --user --wait --pipe).
Use --details for a longer transfer, allowing inspection of the expanded graph.
Use --reopen to verify the same five-app queue survives a close/open/close cycle.
Use --append to add app 6 while app 2 is running and capture both 2/6 displays.
"""
import functools
import gzip
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import sys

ROOT = Path(__file__).resolve().parents[2]
APP = "org.flufflinux.BackgroundTest"
RUNTIME = "org.flufflinux.BackgroundRuntime"


def run(*args, env=None):
    return subprocess.check_output(args, env=env, text=True, stderr=subprocess.STDOUT, timeout=90).strip()


class Throttled(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def copyfile(self, source, output):
        try:
            while data := source.read(32768):
                output.write(data)
                output.flush()
                time.sleep(0.04)  # Actual network transfer; do not fabricate progress.
        except (BrokenPipeError, ConnectionResetError):
            pass  # A cancelled worker closes its HTTP request.


def main():
    assert os.getenv("APPCENTER_MUTATING_TESTS") == "1"
    assert os.geteuid() != 0
    root = Path(tempfile.mkdtemp(prefix="appcenter-background-live-"))
    print("FIXTURE", root, flush=True)
    (root / "runtime").mkdir(mode=0o700)
    (root / "config").mkdir()
    append = "--append" in sys.argv
    reopen = "--reopen" in sys.argv or append
    batch = "--batch" in sys.argv or reopen
    apps = [APP + f".Item{i}" for i in range(1, 7 if append else 6)] if batch else [APP]
    if append:
        qml = "BackgroundAppend.qml"
    elif reopen:
        qml = "BackgroundReopen.qml"
    elif batch:
        qml = "BackgroundBatchFullscreen.qml" if "--fullscreen" in sys.argv else "BackgroundBatch.qml"
    else:
        qml = "BackgroundFullscreen.qml" if "--fullscreen" in sys.argv else "BackgroundLive.qml"
    env = dict(os.environ, FLATPAK_USER_DIR=str(root / "user"), FLATPAK_SYSTEM_DIR=str(root / "system"),
               FLATPAK_CONFIG_DIR=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
               XDG_CACHE_HOME=str(root / "cache"), XDG_CONFIG_HOME=str(root / "settings"),
               XDG_RUNTIME_DIR=str(root / "runtime"), WAYLAND_DISPLAY="/run/user/1000/wayland-0",
               FLUFF_APP_CENTER_QML=str(ROOT / "tests/integration" / qml),
               FLUFF_APP_CENTER_BACKGROUND_TEST="1", QT_FORCE_STDERR_LOGGING="1")
    arch = run("flatpak", "--default-arch")
    for app_id in [RUNTIME, *apps]:
        runtime = app_id == RUNTIME
        build = root / app_id
        payload = build / ("usr" if runtime else "files")
        (payload / "bin").mkdir(parents=True)
        (build / "files").mkdir(exist_ok=True)
        (build / "export").mkdir()
        (build / "metadata").write_text(
            f'[{"Runtime" if runtime else "Application"}]\nname={app_id}\n'
            f'runtime={RUNTIME}/{arch}/stable\nsdk={RUNTIME}/{arch}/stable\n'
            + ("" if runtime else "command=fixture\n"))
        (payload / "bin/fixture").write_text("#!/bin/sh\nexit 0\n")
        (payload / "bin/fixture").chmod(0o755)
        if not runtime:
            number = apps.index(app_id) + 1
            size = (96 if "--details" in sys.argv or reopen else 32) if not batch or number == 2 else 1
            name = f"Test App {number}" if batch else "App Center Test App"
            (payload / "test-payload.bin").write_bytes(os.urandom(size * 1024 * 1024))
            metadata = f'''<component type="desktop-application"><id>{app_id}</id><name>{name}</name>
<summary>Isolated background installation test</summary><metadata_license>CC0-1.0</metadata_license>
<project_license>MIT</project_license><developer_name>FluffNet LLC</developer_name>
<description><p>Real Flatpak background transaction test.</p></description>
<releases><release version="1.0" date="2026-09-27"/></releases><content_rating type="oars-1.1"/>
<launchable type="desktop-id">{app_id}.desktop</launchable></component>'''
            (payload / "share/metainfo").mkdir(parents=True)
            (payload / f"share/metainfo/{app_id}.metainfo.xml").write_text(metadata)
            (payload / "share/applications").mkdir(parents=True)
            (payload / f"share/applications/{app_id}.desktop").write_text(f"[Desktop Entry]\nType=Application\nName={name}\nExec=fixture\n")
            (payload / "share/app-info/xmls").mkdir(parents=True)
            with gzip.open(payload / f"share/app-info/xmls/{app_id}.xml.gz", "wb") as stream:
                stream.write(("<components>" + metadata + "</components>").encode())
        run("flatpak", "build-export", *(["--runtime"] if runtime else []), str(root / "repo"), str(build), "stable", env=env)
    run("flatpak", "build-update-repo", str(root / "repo"), env=env)
    run("flatpak", "remote-add", "--user", "--no-gpg-verify", "background-test", str(root / "repo"), env=env)
    run("flatpak", "install", "--user", "--noninteractive", "--no-related", "background-test", RUNTIME, env=env)
    run("flatpak", "update", "--user", "--appstream", "background-test", env=env)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Throttled, directory=str(root / "repo")))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_port}"
    run("flatpak", "remote-modify", "--user", "--url=" + url, "background-test", env=env)
    unit = "appcenter-background-live-" + root.name.rsplit("-", 1)[-1]
    run("systemd-run", "--user", "--collect", "--unit=" + unit,
        "env", *(f"{key}={value}" for key, value in env.items() if key in {
            "FLATPAK_USER_DIR", "FLATPAK_SYSTEM_DIR", "FLATPAK_CONFIG_DIR", "XDG_DATA_HOME", "XDG_CACHE_HOME",
            "XDG_CONFIG_HOME", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "FLUFF_APP_CENTER_QML", "FLUFF_APP_CENTER_BACKGROUND_TEST",
            "QT_FORCE_STDERR_LOGGING"}), str(ROOT / "target/release/flufflinux-appcenter"))
    print("UNIT", unit, flush=True)
    started = time.monotonic()
    captured = False
    showing_desktop = None
    cycle_captures = set()
    try:
        while time.monotonic() - started < 180:
            log = run("journalctl", "--user", "-u", unit, "-o", "cat", "--no-pager")
            if "BACKGROUND_FAIL" in log:
                raise AssertionError(log)
            for marker, filename in [("BACKGROUND_REOPEN:", "background-reopened.png"),
                                     ("BACKGROUND_RECLOSE:", "background-reclosed.png")]:
                if reopen and marker in log and marker not in cycle_captures:
                    time.sleep(.5)
                    run("spectacle", "-b", "-n", "-f", "-o", str(root / filename))
                    cycle_captures.add(marker)
                    print("QUEUE_CYCLE_CAPTURE", filename, flush=True)
            marker = "BACKGROUND_TRANSFER_2_OF_5" if batch else "BACKGROUND_TRANSFER"
            if marker in log and not captured:
                if "--desktop" in sys.argv and "--fullscreen" not in sys.argv:
                    # Reversible presentation-only step for clean screenshots;
                    # never close or modify the user's other windows/files.
                    showing_desktop = run("qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.showingDesktop")
                    run("qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.showDesktop", "true")
                time.sleep(7)  # Allow PowerDevil's own pending-inhibition delay.
                run("spectacle", "-b", "-n", "-f", "-o", str(root / "background-progress.png"))
                inhibitors = run("qdbus6", "--literal", "org.kde.Solid.PowerManagement", "/org/kde/Solid/PowerManagement/PolicyAgent",
                                 "org.kde.Solid.PowerManagement.PolicyAgent.ListInhibitions")
                assert "App Center" in inhibitors, inhibitors
                if "--fullscreen" in sys.argv:
                    inhibited = run("qdbus6", "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications.Inhibited")
                    assert inhibited == "true", "KDE fullscreen suppression did not activate: " + inhibited
                    print("FULLSCREEN_SUPPRESSED", flush=True)
                print("SLEEP_INHIBITED", inhibitors, flush=True)
                captured = True
            if "BACKGROUND_COMPLETE" in log:
                time.sleep(.5)
                run("spectacle", "-b", "-n", "-f", "-o", str(root / "background-complete.png"))
                (root / "journal.txt").write_text(log)
                installed = run("flatpak", "list", "--user", "--app", "--columns=application", env=env).splitlines()
                assert all(app_id in installed for app_id in apps), installed
                if reopen:
                    assert len(cycle_captures) == 2, cycle_captures
                inhibitors = run("qdbus6", "--literal", "org.kde.Solid.PowerManagement", "/org/kde/Solid/PowerManagement/PolicyAgent",
                                 "org.kde.Solid.PowerManagement.PolicyAgent.ListInhibitions")
                assert "App Center" not in inhibitors, inhibitors
                print("PASS real background install; inhibitor released; screenshots:", root, flush=True)
                return
            time.sleep(.25)
        raise AssertionError("Background installation timed out")
    finally:
        subprocess.run(["systemctl", "--user", "stop", unit], check=False)
        if showing_desktop is not None:
            run("qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.showDesktop", showing_desktop)
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
