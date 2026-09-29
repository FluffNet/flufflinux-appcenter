"""Capture real source-failure UI without disconnecting the user's VM.

NM states are simulated on a private bus. The production Flatpak worker tries
real Flathub through a refusing proxy, using disposable source/config data.
"""
import os
import http.server
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import threading

repo = Path(__file__).resolve().parents[2]
binary = str(Path(sys.argv[1]).resolve())
preview = str(repo / "target/network-preview")
display = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
if not display.startswith("/"):
    display = str(Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / display)
with tempfile.TemporaryDirectory(prefix="appcenter-network-capture-") as directory:
    root = Path(directory)
    env = dict(os.environ, XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
               XDG_CACHE_HOME=str(root / "cache"), XDG_RUNTIME_DIR=str(root / "runtime"),
               FLATPAK_USER_DIR=str(root / "user"), FLATPAK_SYSTEM_DIR=str(root / "system"),
               FLATPAK_CONFIG_DIR=str(root / "flatpak-config"), WAYLAND_DISPLAY=display,
               QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="software", QT_FORCE_STDERR_LOGGING="1",
               FLUFF_APP_CENTER_QML=str(repo / "tests/integration/CatalogFailureSmoke.qml"),
               FLUFF_APP_CENTER_CATALOG_TEST="1", FLUFF_APP_CENTER_BACKGROUND_TEST="1")
    for name in ("runtime", "config", "flatpak-config"):
        (root / name).mkdir(mode=0o700)
    # Match the user's KDE colors while keeping all test writes isolated.
    theme = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "kdeglobals"
    if theme.is_file():
        shutil.copyfile(theme, root / "config/kdeglobals")
    (root / "config/flufflinux-appcenter.conf").write_text("[Sources]\ninitialized=true\n")

    def command(*args):
        result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=90)
        assert result.returncode == 0, result.stderr
        return result

    for scope in ("user", "system"):
        (root / scope).mkdir()
        command("ostree", "--repo=" + str(root / scope / "repo"), "init", "--mode=bare-user-only")
    command("flatpak", "remote-add", "--user", "--from", "flathub", "https://dl.flathub.org/repo/flathub.flatpakrepo")
    private_bus = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    requests = []
    class RefusingProxy(http.server.BaseHTTPRequestHandler):
        def do_CONNECT(self):
            requests.append(self.path)
            self.send_error(503, "No Internet connection in isolated test")
        do_GET = do_CONNECT
        def log_message(self, *args):
            pass
    proxy = http.server.ThreadingHTTPServer(("127.0.0.1", 0), RefusingProxy)
    threading.Thread(target=proxy.serve_forever, daemon=True).start()
    try:
        address = private_bus.stdout.readline().strip()
        assert address.startswith("unix:")
        proxy_url = f"http://127.0.0.1:{proxy.server_port}"
        env.update(APPCENTER_PREVIEW_BUS=address, DBUS_SYSTEM_BUS_ADDRESS=address,
                   http_proxy=proxy_url, https_proxy=proxy_url,
                   HTTP_PROXY=proxy_url, HTTPS_PROXY=proxy_url, no_proxy="", NO_PROXY="")
        for state, name in ((50, "lan"), (20, "offline")):
            before = len(requests)
            nm = subprocess.Popen([preview, str(state)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                assert nm.stdout.readline().strip() == "READY"
                result = command(binary)
                (repo / f"target/cache-{name}-capture.log").write_text(result.stdout + result.stderr)
                print(result.stdout + result.stderr, flush=True)
                assert "CATALOG_FAILURE_CAPTURE" in result.stderr
                if name == "lan":
                    assert "REAL_SOURCE_ERROR" in result.stderr
                    assert any("flathub.org" in request for request in requests[before:]), requests
                    print("BLOCKED_FLATHUB_REQUESTS", requests[before:], flush=True)
                else:
                    assert "REAL_SOURCE_ERROR" not in result.stderr
                    assert len(requests) == before, "Fully offline must not attempt a source refresh"
                assert not list((root / "cache").rglob("application-list.json")), "Failed/offline refresh must not create a fresh cache"
            finally:
                nm.terminate()
                nm.wait(timeout=5)
        assert not (root / "user/app").exists() and not (root / "system/app").exists()
        print("PASS: real Flathub failure, LAN allowed, offline deferred, no queue/notification job, no cache renewal; VM network unchanged")
    finally:
        proxy.shutdown()
        proxy.server_close()
        private_bus.terminate()
        private_bus.wait(timeout=5)
