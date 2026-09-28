"""Read-only native startup timing with a private single-instance socket."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

binary = str(Path(sys.argv[1]).resolve())
fixture = str(Path(__file__).with_name("StartupSmoke.qml").resolve())
env = os.environ.copy()
display = env.get("WAYLAND_DISPLAY", "wayland-0")
if not display.startswith("/"):
    display = str(Path(env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / display)
with tempfile.TemporaryDirectory(prefix="appcenter-startup-") as runtime:
    env.update(XDG_RUNTIME_DIR=runtime, WAYLAND_DISPLAY=display,
               XDG_CACHE_HOME=env.get("APPCENTER_TEST_CACHE_HOME", str(Path(runtime) / "cache")),
               QT_QPA_PLATFORM="wayland", QT_FORCE_STDERR_LOGGING="1",
               QT_QUICK_BACKEND="software", FLUFF_APP_CENTER_QML=fixture,
               FLUFF_APP_CENTER_TRACE_STARTUP="1")
    started = time.monotonic()
    process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True)
    first_frame = None
    early_result = []
    early_thread = None
    received_search = False
    def activate_during_startup():
        result = subprocess.run([binary, "--mode=Browsing"], env=env, capture_output=True, timeout=18)
        early_result.append((time.monotonic() - started, result.returncode))
    try:
        for line in process.stdout:
            if "APPCENTER_STARTUP qt-ready" in line and "--early" in sys.argv and early_thread is None:
                early_thread = threading.Thread(target=activate_during_startup)
                early_thread.start()
            if "STARTUP_" in line or "APPCENTER_STARTUP" in line:
                elapsed = time.monotonic() - started
                print(f"{elapsed:.3f}s {line.strip()}", flush=True)
            if "STARTUP_FIRST_FRAME" in line:
                first_frame = time.monotonic() - started
            if "STARTUP_CLI_SEARCH_RECEIVED" in line:
                received_search = True
            if "STARTUP_CATALOG" in line:
                activation = time.monotonic()
                result = subprocess.run([binary, "telegram"], env=env, capture_output=True, timeout=15)
                print(f"CLI_ACTIVATION_SECONDS={time.monotonic() - activation:.3f} exit={result.returncode}", flush=True)
                assert result.returncode == 0, result.stderr
        result = process.wait(timeout=25)
        assert result == 0 and first_frame is not None, f"Startup failed: exit={result}, frame={first_frame}"
        assert received_search, "CLI search was not delivered to the original window"
        if early_thread:
            early_thread.join(timeout=20)
            assert early_result and early_result[0][1] == 0, early_result
            # Receipt of the frame log may trail the actual swap by a few ms.
            assert early_result[0][0] >= first_frame - 0.025, (early_result, first_frame)
            print(f"EARLY_LAUNCHER_EXIT_SECONDS={early_result[0][0]:.3f} (after first frame)", flush=True)
        print(f"FIRST_FRAME_SECONDS={first_frame:.3f}", flush=True)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
