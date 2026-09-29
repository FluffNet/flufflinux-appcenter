#!/usr/bin/env python3
"""Exercise first-launch and single-instance legacy update dispatch offscreen."""
from pathlib import Path
import os
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[2]
binary = repo / "target/release/flufflinux-appcenter"
with tempfile.TemporaryDirectory(prefix="appcenter-legacy-launch-") as temporary:
    root = Path(temporary)
    root.chmod(0o700)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(root), XDG_CONFIG_HOME=str(root / "config"),
               XDG_CACHE_HOME=str(root / "cache"), QT_QPA_PLATFORM="offscreen",
               QT_QUICK_BACKEND="software", QT_FORCE_STDERR_LOGGING="1",
               FLUFF_APP_CENTER_QML=str(repo / "tests/integration/LegacyUpdatesSmoke.qml"))
    for args in (["--updates"], ["--mode", "update"], ["--mode=update"]):
        result = subprocess.run([binary, *args], env=env, capture_output=True, text=True, timeout=20)
        assert result.returncode == 0 and "PASS: legacy" in result.stderr, result.stderr
    first = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        for _ in range(100):
            if (root / "flufflinux-appcenter.socket").exists():
                break
            assert first.poll() is None, first.communicate()
            time.sleep(0.05)
        result = subprocess.run([binary, "--mode", "update"], env=env, capture_output=True, text=True, timeout=20)
        out, err = first.communicate(timeout=15)
        assert result.returncode == first.returncode == 0 and "PASS: legacy" in err, (result.stderr, err)
    finally:
        if first.poll() is None:
            first.terminate()
            first.wait(timeout=5)
print("PASS: first launch and existing-instance Discover update actions")
