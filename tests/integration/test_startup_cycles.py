"""Measure 20 installed GUI open/close cycles, alternating new and live processes.

Reads the real catalog/cache, but uses a private IPC socket and non-persistent
window settings. The app closes through its real background queue controller.
"""
import json
import os
from pathlib import Path
import queue
import statistics
import subprocess
import sys
import tempfile
import threading
import time

binary = str(Path(sys.argv[1]).resolve())
scripts = Path(__file__).resolve().parent
results = []
with tempfile.TemporaryDirectory(prefix="appcenter-startup-cycles-") as directory:
    root = Path(directory)
    assets = Path("/usr/share/flufflinux-appcenter/qml") if binary == "/usr/bin/flufflinux-appcenter" else scripts.parents[1] / "qml"
    driver = root / "Cycles.qml"
    driver.write_text((scripts / "StartupCycleSmoke.qml").read_text().replace('"../../qml"', json.dumps(assets.as_uri())))
    display = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
    if not display.startswith("/"):
        display = str(Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / display)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(root), WAYLAND_DISPLAY=display,
               FLUFF_APP_CENTER_QML=str(driver), FLUFF_APP_CENTER_CATALOG_TEST="1",
               FLUFF_APP_CENTER_BACKGROUND_TEST="1", FLUFF_APP_CENTER_TRACE_STARTUP="1",
               QT_FORCE_STDERR_LOGGING="1")
    process = None
    lines = queue.Queue()

    def collect(child):
        for line in child.stdout:
            lines.put((time.monotonic(), line.strip()))

    def wait_for(marker, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            stamp, line = lines.get(timeout=max(.1, deadline - time.monotonic()))
            if "CYCLE_" in line or "APPCENTER_STARTUP" in line:
                print(line, flush=True)
            if marker in line:
                return stamp, line
        raise AssertionError("Timed out waiting for " + marker)

    try:
        for cycle in range(1, 21):
            started = time.monotonic()
            new_process = cycle % 2 == 1
            if new_process:
                assert process is None or process.poll() == 0
                process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                threading.Thread(target=collect, args=(process,), daemon=True).start()
            else:
                assert process.poll() is None, "Process exited before the quick reopen"
                launcher = subprocess.run([binary], env=env, text=True, capture_output=True, timeout=20)
                assert launcher.returncode == 0, launcher.stderr
            stamp, line = wait_for("CYCLE_READY")
            result = {"cycle": cycle, "mode": "new-process" if new_process else "quick-reopen",
                      "pid": process.pid, "readySeconds": round(stamp - started, 3)}
            results.append(result)
            print("RESULT " + json.dumps(result), flush=True)
            wait_for("CYCLE_CLOSED")
            if not new_process:
                process.wait(timeout=15)
                assert process.returncode == 0
    finally:
        if process and process.poll() is None:
            process.terminate(); process.wait(timeout=10)

for mode in ("new-process", "quick-reopen"):
    times = [result["readySeconds"] for result in results if result["mode"] == mode]
    print("SUMMARY " + json.dumps({"mode": mode, "count": len(times), "min": min(times),
                                  "median": round(statistics.median(times), 3), "max": max(times)}))
print("PASS: 20 real GUI open/close cycles; each displayed the app list before closing")
