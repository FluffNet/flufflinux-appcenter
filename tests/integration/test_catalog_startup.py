"""Real GUI + libflatpak + HTTP source: cold, <12h and expired startup.

Only temporary source/config/cache directories are changed. No apps installed.
"""
import datetime
import functools
import gzip
import http.server
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import time

binary = str(Path(sys.argv[1]).resolve())
benchmark = Path(__file__).with_name("benchmark_startup.py")
with tempfile.TemporaryDirectory(prefix="appcenter-catalog-cache-") as directory:
    root = Path(directory)
    env = dict(os.environ, APPCENTER_TEST_CACHE_HOME=str(root / "cache"),
               XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
               FLATPAK_USER_DIR=str(root / "user"), FLATPAK_SYSTEM_DIR=str(root / "system"),
               FLATPAK_CONFIG_DIR=str(root / "flatpak-config"), FLUFF_APP_CENTER_CATALOG_TEST="1")
    for name in ("config", "flatpak-config", "metadata"):
        (root / name).mkdir()
    (root / "config/flufflinux-appcenter.conf").write_text("[Sources]\ninitialized=true\n")

    def command(*args):
        result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, (args, result.stderr)
        return result.stdout

    for scope in ("user", "system"):
        (root / scope).mkdir()
        command("ostree", "--repo=" + str(root / scope / "repo"), "init", "--mode=bare-user-only")
    repository = root / "repository"
    command("ostree", "--repo=" + str(repository), "init", "--mode=archive-z2")
    arch = command("flatpak", "--default-arch").strip()

    def publish(extra=False):
        ids = ["com.brave.Browser"] + [f"org.example.App{i}" for i in range(3300)]
        if extra:
            ids.append("org.example.JustPublished")
        xml = "<components>" + "".join(
            f'<component type="desktop-application"><id>{app}</id><name>{app}</name>'
            f'<summary>Cache integration test</summary><bundle type="flatpak">app/{app}/{arch}/stable</bundle>'
            '</component>' for app in ids) + "</components>"
        (root / "metadata/appstream.xml.gz").write_bytes(gzip.compress(xml.encode()))
        command("ostree", "--repo=" + str(repository), "commit", "--branch=appstream/" + arch,
                "--subject=Test catalog", "--tree=dir=" + str(root / "metadata"))
        command("ostree", "--repo=" + str(repository), "summary", "--update")

    requests = []
    class Handler(http.server.SimpleHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            time.sleep(0.25)  # Make the pre-refresh first frame observable.
            super().do_GET()
        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=str(repository)))
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        publish()
        command("flatpak", "remote-add", "--user", "--no-gpg-verify", "fixture", f"http://127.0.0.1:{server.server_port}")

        def launch(label):
            result = subprocess.run([sys.executable, str(benchmark), binary, "--early"],
                                    env=env, text=True, capture_output=True, timeout=90)
            print(f"{label}:\n{result.stdout}", flush=True)
            assert result.returncode == 0, result.stderr + result.stdout
            first = re.search(r"STARTUP_FIRST_FRAME apps (\d+) loading (true|false)", result.stdout)
            assert first, result.stdout
            return int(first[1]), first[2] == "true", result.stdout

        count, loading, _ = launch("COLD")
        assert count == 0 and loading
        cache, = (root / "cache").rglob("application-list.json")
        data = json.loads(cache.read_text())
        assert len(data["apps"]) == 3301
        timestamp = cache.stat().st_mtime_ns
        publish(extra=True)
        request_count = len(requests)
        count, loading, output = launch("WARM")
        assert count == len(data["apps"]) and not loading
        assert "catalog-cache-ready" in output
        assert cache.stat().st_mtime_ns == timestamp
        assert len(requests) == request_count, "Fresh cache must not contact the sources"

        data["savedAt"] = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=12)).isoformat(timespec="milliseconds")
        cache.write_text(json.dumps(data))
        count, loading, _ = launch("EXPIRED")
        assert count == 0 and loading, "Expired apps must not appear while refreshing"
        updated = json.loads(cache.read_text())
        assert updated["savedAt"] != data["savedAt"]
        assert any(app["id"] == "org.example.JustPublished" for app in updated["apps"])
        assert len(requests) > request_count, "Expired startup must actually fetch source metadata"
        assert not (root / "user/app").exists() and not (root / "system/app").exists()
        print("PASS: no warm network/rebuild, expired empty loading screen, HTTP source refreshed, newly published app appears, cache timer renewed; no installed-app changes")
    finally:
        server.shutdown()
        server.server_close()
