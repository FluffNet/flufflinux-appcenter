"""Three install/remove cycles while size pages stay open. Only temporary Flatpaks."""
import gzip
import functools
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
import random
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

binary = str(Path(sys.argv[1]).resolve())
project = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="appcenter-size-cycle-") as directory:
    root = Path(directory)
    for name in ("config", "flatpak-config", "runtime"):
        (root / name).mkdir(mode=0o700)
    (root / "config/flufflinux-appcenter.conf").write_text("[Sources]\ninitialized=true\n")
    env = dict(os.environ, XDG_CONFIG_HOME=str(root / "config"),
               XDG_DATA_HOME=str(root / "data"), XDG_CACHE_HOME=str(root / "cache"),
               XDG_RUNTIME_DIR=str(root / "runtime"),
               FLATPAK_USER_DIR=str(root / "user"), FLATPAK_SYSTEM_DIR=str(root / "system"),
               FLATPAK_CONFIG_DIR=str(root / "flatpak-config"),
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               QT_QUICK_CONTROLS_STYLE="org.kde.desktop", QT_FORCE_STDERR_LOGGING="1")

    def run(*args):
        reply = subprocess.run(args, env=env, text=True, capture_output=True, timeout=60)
        assert reply.returncode == 0, (args, reply.stdout, reply.stderr)
        return reply.stdout.strip()

    arch = run("flatpak", "--default-arch")
    runtime = "org.example.SizeCycle.Runtime"
    for app in [runtime, "org.example.SizeCycle.App1", "org.example.SizeCycle.App2"]:
        is_runtime = app == runtime
        build = root / app
        payload = build / ("usr" if is_runtime else "files")
        (payload / "bin").mkdir(parents=True)
        (build / "files").mkdir(exist_ok=True)
        (build / "export").mkdir()
        (build / "metadata").write_text(
            f'[{"Runtime" if is_runtime else "Application"}]\nname={app}\n'
            f'runtime={runtime}/{arch}/stable\nsdk={runtime}/{arch}/stable\n'
            + ("" if is_runtime else "command=fixture\n"))
        (payload / "bin/fixture").write_text("#!/bin/sh\nexit 0\n")
        (payload / "bin/fixture").chmod(0o755)
        (payload / "payload.bin").write_bytes(random.Random(app).randbytes(
            512 * 1024 if is_runtime else 256 * 1024))
        if not is_runtime:
            metadata = f'''<component type="desktop-application"><id>{app}</id><name>{app}</name>
<summary>Isolated size lifecycle fixture</summary><metadata_license>CC0-1.0</metadata_license>
<project_license>MIT</project_license><description><p>Size test.</p></description>
<launchable type="desktop-id">{app}.desktop</launchable></component>'''
            (payload / "share/metainfo").mkdir(parents=True)
            (payload / f"share/metainfo/{app}.metainfo.xml").write_text(metadata)
            (payload / "share/app-info/xmls").mkdir(parents=True)
            (payload / f"share/app-info/xmls/{app}.xml.gz").write_bytes(
                gzip.compress(("<components>" + metadata + "</components>").encode()))
            (payload / "share/applications").mkdir(parents=True)
            (payload / f"share/applications/{app}.desktop").write_text(
                f"[Desktop Entry]\nType=Application\nName=Size fixture\nExec=fixture\n")
        run("flatpak", "build-export", *(["--runtime"] if is_runtime else []),
            str(root / "repo"), str(build), "stable")
    run("flatpak", "build-update-repo", str(root / "repo"))
    requests = []
    class QuietHandler(SimpleHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def do_GET(self):
            requests.append(self.path)
            super().do_GET()
    server = ThreadingHTTPServer(("127.0.0.1", 0),
        functools.partial(QuietHandler, directory=str(root / "repo")))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = f"http://127.0.0.1:{server.server_port}"
    run("flatpak", "remote-add", "--user", "--no-gpg-verify", "size-cycle", url)
    run("flatpak", "remote-ls", "--user", "size-cycle")
    env["FLUFF_APP_CENTER_QML"] = str(project / "tests/integration/SizeLifecycleSmoke.qml")
    env["FLUFF_APP_CENTER_CATALOG_TEST"] = "1"
    result = subprocess.run(["dbus-run-session", "--", binary], env=env,
                            text=True, capture_output=True, timeout=140)
    print("\n".join(line for line in result.stderr.splitlines() if "SIZE_LIFECYCLE" in line))
    if result.returncode:
        print(result.stderr[-5000:])
        for app in ["org.example.SizeCycle.App1", "org.example.SizeCycle.App2"]:
            print("DIRECT_SIZE", app, run(binary, "--sizes-worker", json.dumps(
                dict(id=app,remote="size-cycle",sourceUrl=url,flatpakRef=f"app/{app}/{arch}/stable"))))
        print("CACHE_FILES", [str(p.relative_to(root)) for p in root.rglob("*summary*")])
        cached = subprocess.run(["flatpak","remote-ls","--user","--cached","size-cycle"],
                                env=env,capture_output=True,text=True)
        print("CACHED_REFS", cached.returncode, cached.stdout, cached.stderr)
    assert result.returncode == 0, result.returncode
    assert "SIZE_LIFECYCLE_PASS" in result.stderr
    assert not run("flatpak", "list", "--user", "--app", "--columns=application")
    request = dict(id="org.example.SizeCycle.App1",remote="size-cycle",sourceUrl=url,
                   flatpakRef=f"app/org.example.SizeCycle.App1/{arch}/stable")
    def size(values):
        return json.loads(run(binary, "--sizes-worker", json.dumps(values)))
    before = len(requests)
    warm = size(request)
    assert warm["state"] == "ready", warm
    assert len(requests) == before, "A warm size page fetched source metadata"
    run("flatpak", "uninstall", "--user", "--noninteractive", runtime)
    cached = subprocess.run(["flatpak","remote-ls","--user","--cached","size-cycle"],
                            env=env,capture_output=True,text=True)
    assert cached.returncode != 0, "Fixture did not reproduce summary eviction"
    before = len(requests)
    restored = size(request)
    assert restored["state"] == "ready" and restored["totalBytes"] > restored["appBytes"], restored
    fetched = requests[before:]
    assert fetched and not any("/objects/" in path or "/deltas/" in path for path in fetched), fetched
    before = len(requests)
    assert size(request)["state"] == "ready"
    assert size(dict(request, id="org.example.SizeCycle.App2",
                     flatpakRef=f"app/org.example.SizeCycle.App2/{arch}/stable"))["state"] == "ready"
    assert len(requests) == before, "Recovered summary was not reused for other apps"
    assert size(dict(request, sourceUrl=url+"/changed"))["state"] == "unavailable"
    run("flatpak", "remote-modify", "--user", "--disable", "size-cycle")
    assert size(request)["state"] == "unavailable"
    assert len(requests) == before, "Disabled or mismatched source was fetched"
    run("flatpak", "remote-modify", "--user", "--enable", "size-cycle")
    # Simulate another eviction inside this test's private installation.
    # Offline reads must fail normally. The manager retains known app size.
    shutil.rmtree(root / "user/repo/tmp/cache", ignore_errors=True)
    server.shutdown()
    server.server_close()
    offline = size(request)
    assert offline["state"] == "unavailable", offline
    print("PASS: both app size fields survive three install/remove cycles in one GUI process")
    print("PASS: metadata-only summary recovery, warm reuse without network, correct runtime totals, disabled/changed sources and offline failure")
