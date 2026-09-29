#!/usr/bin/env python3
"""Discover feedback compatibility: no GUI, service, IPC or profile changes."""
from pathlib import Path
import os
import socket
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
binary = Path(os.environ.get("APPCENTER_TEST_BINARY", repo / "target/release/flufflinux-appcenter")).resolve()
with tempfile.TemporaryDirectory(prefix="appcenter-feedback-") as temporary:
    root = Path(temporary)
    profile = root / "profile"
    runtime = profile / "runtime"
    runtime.mkdir(parents=True, mode=0o700)
    aliases = root / "bin"
    aliases.mkdir()
    for name in ("flufflinux-appcenter", "plasma-discover", "discover", "flufflinux-discover"):
        (aliases / name).symlink_to(binary)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(profile / "config"),
               XDG_CACHE_HOME=str(profile / "cache"), XDG_DATA_HOME=str(profile / "data"),
               QT_QPA_PLATFORM="not-a-platform", FLUFF_APP_CENTER_QML=str(root / "missing.qml"))

    def check_probes():
        before = set(profile.rglob("*"))
        for executable in sorted(aliases.iterdir()):
            for args in (["--feedback"], ["--desktopfile=org.kde.discover.desktop", "--feedback"],
                         ["--feedback", "--mode=Update"]):
                result = subprocess.run([executable, *args], env=env, capture_output=True,
                                        text=True, timeout=5)
                assert result.returncode == 0, (executable, args, result)
                assert not result.stdout and not result.stderr, (executable, args, result)
                assert set(profile.rglob("*")) == before, "Feedback probe wrote profile data"

    # No instance: even missing QML and an invalid Qt platform must be harmless.
    check_probes()
    # Existing/hidden instance: a feedback probe must not send activation or search.
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
        listener.bind(str(runtime / "flufflinux-appcenter.socket"))
        listener.listen(64)
        listener.setblocking(False)
        check_probes()
        try:
            connection, _ = listener.accept()
        except BlockingIOError:
            pass
        else:
            connection.close()
            raise AssertionError("Feedback probe contacted the running instance")
print("PASS: feedback exits silently through all four executable names, no GUI or IPC, no profile changes")
