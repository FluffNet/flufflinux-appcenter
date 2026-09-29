#!/usr/bin/env python3
"""Exercise the desktop Exec line and real CLI with isolated, read-only IPC.

The receiver records launch requests only. No UI worker, repository changes or
installations are started. Run with --defaults after installing the package to
also check the system's actual MIME defaults through gio open.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="appcenter-desktop-routing-") as temporary:
    root = Path(temporary)
    root.chmod(0o700)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(root), XDG_CACHE_HOME=str(root / "cache"),
               QT_QPA_PLATFORM="offscreen", QT_FORCE_STDERR_LOGGING="1",
               PATH=str(repo / "target/release") + os.pathsep + os.environ["PATH"])
    receiver = socket.socket(socket.AF_UNIX)
    receiver.bind(str(root / "flufflinux-appcenter.socket"))
    receiver.listen(2)
    receiver.settimeout(30)
    def check(arguments, expected):
        child = subprocess.Popen(arguments, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            connection, _ = receiver.accept()
            with connection:
                connection.settimeout(15)
                payload = b""
                while b"\n" not in payload:
                    chunk = connection.recv(65536)
                    assert chunk, payload
                    payload += chunk
            def canonical(action):
                # GIO may expand a local %U item as either a file URL or an
                # absolute filename. Both must retain one exact argument.
                value = action["value"]
                if value.startswith("file://"):
                    url = urlsplit(value)
                    assert url.netloc in ("", "localhost"), value
                    value = unquote(url.path)
                elif value.startswith("appstream://"):
                    value = value.removesuffix("/")
                return {"type": action["type"], "value": value}
            assert [canonical(action) for action in json.loads(payload)] == [canonical(action) for action in expected], payload
            output, errors = child.communicate(timeout=20)
            assert child.returncode == 0, (output, errors)
        finally:
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=10)

    desktop = repo / "data/flufflinux-appcenter.desktop"
    files = []
    for extension in ("flatpak", "flatpakref", "flatpakrepo"):
        path = root / ("Space # Unicode \u00e9." + extension)
        # Empty files have the special inode/x-empty MIME type regardless of
        # extension. Use recognizable headers for the default-handler check.
        path.write_bytes({"flatpak": b"\x00Flatpak desktop routing fixture\x00",
                          "flatpakref": b"[Flatpak Ref]\nName=org.example.App\n",
                          "flatpakrepo": b"[Flatpak Repo]\nTitle=Routing test\n"}[extension])
        files.append(path)
        check(["gio", "launch", str(desktop), str(path)],
              [{"type": "source", "value": path.as_uri()}])
    check(["gio", "launch", str(desktop), *(str(path) for path in files)],
          [{"type": "source", "value": path.as_uri()} for path in files])
    link = "appstream://org.example.App"
    check(["gio", "launch", str(desktop), link], [{"type": "installed-application", "value": link}])
    if "--defaults" in sys.argv:
        # MIME default tests use the installed executable, not the source build.
        env["PATH"] = os.environ["PATH"]
        for extension, mime in (("flatpak", "application/vnd.flatpak"),
                                ("flatpakref", "application/vnd.flatpak.ref"),
                                ("flatpakrepo", "application/vnd.flatpak.repo")):
            name = subprocess.check_output(["xdg-mime", "query", "default", mime], text=True).strip()
            assert name in {"flufflinux-appcenter.desktop", "org.kde.discover.desktop",
                            "org.kde.discover.flatpak.desktop", "org.kde.discover.urlhandler.desktop"}, name
            path = next(path for path in files if path.suffix == "." + extension)
            check(["gio", "open", str(path)], [{"type": "source", "value": path.as_uri()}])
        check(["gio", "open", link], [{"type": "installed-application", "value": link}])
    receiver.close()
print("PASS: desktop file activation, all three Flatpak types, spaces/Unicode/URL escaping, multiple files, installed-only AppStream routing")
