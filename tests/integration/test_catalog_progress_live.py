"""Time fresh Flathub pulls and warm reopening, capturing the real loading UI.

Uses disposable, empty Flatpak installations plus config/cache/runtime roots.
Does not delete the user's cache, install apps or modify their sources/theme.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import time

repo = Path(__file__).resolve().parents[2]
binary = str(Path(sys.argv[1]).resolve())
# Limit only this test and its children to two CPUs, matching the fresh VM's
# CPU count without changing the VM configuration or any other process.
cpus = sorted(os.sched_getaffinity(0))[:2]
os.sched_setaffinity(0, cpus)
print("BENCHMARK_CPUS", cpus, flush=True)
display = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
if not display.startswith("/"):
    display = str(Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / display)
results = []
for theme in ("dark", "light"):
    with tempfile.TemporaryDirectory(prefix="appcenter-clean-progress-") as directory:
        root = Path(directory)
        for name in ("runtime", "config", "flatpak-config", "user", "system"):
            (root / name).mkdir(mode=0o700)
        fixture = "CatalogProgressLightSmoke.qml" if theme == "light" else "CatalogProgressSmoke.qml"
        env = dict(os.environ, XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
                   XDG_CACHE_HOME=str(root / "cache"), XDG_RUNTIME_DIR=str(root / "runtime"),
                   FLATPAK_USER_DIR=str(root / "user"), FLATPAK_SYSTEM_DIR=str(root / "system"),
                   FLATPAK_CONFIG_DIR=str(root / "flatpak-config"), WAYLAND_DISPLAY=display,
                   QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="software", QT_FORCE_STDERR_LOGGING="1",
                   FLUFF_APP_CENTER_QML=str(repo / "tests/integration" / fixture),
                   FLUFF_APP_CENTER_CATALOG_TEST="1", FLUFF_APP_CENTER_TRACE_STARTUP="1")
        for scope in ("user", "system"):
            subprocess.run(["ostree", "--repo=" + str(root / scope / "repo"), "init", "--mode=bare-user-only"],
                           env=env, check=True, capture_output=True, timeout=20)
        assert not (root / "cache").exists()
        assert not list(root.rglob("appstream.xml*"))
        # App Center itself provisions Flathub during the measured first run.
        for mode in ("cold", "warm"):
            before = list((root / "cache").rglob("application-list.json"))
            if mode == "cold":
                assert not before
            else:
                assert len(before) == 1
            saved = before[0].read_bytes() if before else None
            stamp = before[0].stat().st_mtime_ns if before else None
            start = time.monotonic()
            process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            watchdog = threading.Timer(260, process.kill)
            watchdog.start()
            lines, progress = [], []
            first = ready = None
            try:
                for line in process.stdout:
                    elapsed = time.monotonic() - start
                    lines.append(f"{elapsed:.3f}s {line.rstrip()}")
                    if "CATALOG_" in line or "APPCENTER_STARTUP" in line:
                        print(f"{theme} {mode} {elapsed:.3f}s {line.rstrip()}", flush=True)
                    match = re.search(r"CATALOG_PROGRESS (\d+)", line)
                    if match:
                        progress.append(int(match[1]))
                    if "CATALOG_FIRST_FRAME" in line:
                        first = elapsed
                        assert ("loading true" in line) == (mode == "cold"), line
                    if "CATALOG_READY_FRAME" in line:
                        ready = elapsed
                assert process.wait(timeout=10) == 0, "\n".join(lines)
            finally:
                watchdog.cancel()
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)
                (repo / f"target/loading-{theme}-{mode}.log").write_text("\n".join(lines) + "\n")
            assert first is not None and ready is not None
            assert progress == sorted(progress), progress
            if mode == "cold":
                assert any(10 <= value < 70 for value in progress), progress
                assert any(70 <= value < 100 for value in progress) and progress[-1] == 100
            cache, = (root / "cache").rglob("application-list.json")
            data = json.loads(cache.read_text())
            assert len(data["apps"]) > 1000 and data["savedAt"]
            if mode == "warm":
                assert cache.read_bytes() == saved and cache.stat().st_mtime_ns == stamp
                assert not any(0 < value < 100 for value in progress), progress
            assert not (root / "user/app").exists() and not (root / "system/app").exists()
            results.append(dict(theme=theme, mode=mode, cpus=cpus, first_frame_seconds=round(first, 3),
                                ready_seconds=round(ready, 3), apps=len(data["apps"]), progress=progress))
        print(f"PASS: {theme} fresh Flathub pull, monotonic percentage, warm cache without rebuild, no apps installed", flush=True)
(repo / "target/loading-live-results.json").write_text(json.dumps(results, indent=2) + "\n")
print(json.dumps(results, indent=2), flush=True)
