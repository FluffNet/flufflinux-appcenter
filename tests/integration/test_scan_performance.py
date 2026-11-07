"""Compare fully prepared scans; all packages, metadata and sources are temporary."""
import gzip
import http.server
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import tempfile
import threading
import time

from test_full_update_plan import export
from test_updates import command, commit, environment

baseline, candidate = map(lambda p: str(Path(p).resolve()), sys.argv[1:3])

with tempfile.TemporaryDirectory(prefix="appcenter-scan-perf-") as directory:
    root = Path(directory)
    env = environment(root)
    (root / "config").mkdir()
    env.update(HOME=str(root / "home"), APPCENTER_PROFILE_SCAN="1")
    arch = command(env, "flatpak", "--default-arch")
    runtime_id = "org.example.ScanRuntime"
    runtime = f"{runtime_id}/{arch}/stable"
    app_count = int(os.environ.get("APPCENTER_SCAN_STRESS_ITEMS", "30"))
    assert 2 <= app_count <= 200
    apps = [f"org.example.ScanApp{i:02}" for i in range(app_count)]
    for version in (1, 2):
        export(env, root, runtime_id, runtime, version, True)
        for index, app in enumerate(apps):
            build = export(env, root, app, runtime, version)
            metadata = build / "metadata"
            if version == 2 and index % 2 == 0:
                metadata.write_text(metadata.read_text() + "shared=network;\n")
            payload = build / "files"
            component = f'''<component type="desktop-application"><id>{app}</id><name>{app}</name>
<summary>Scan fixture</summary><metadata_license>CC0-1.0</metadata_license><project_license>MIT</project_license>
<releases><release version="{version}.0" date="2026-11-0{version}"/></releases>
<launchable type="desktop-id">{app}.desktop</launchable></component>'''
            (payload / "share/app-info/xmls").mkdir(parents=True)
            (payload / f"share/app-info/xmls/{app}.xml.gz").write_bytes(
                gzip.compress(("<components>" + component + "</components>").encode()))
            (payload / "share/metainfo").mkdir(parents=True)
            (payload / f"share/metainfo/{app}.metainfo.xml").write_text(component)
            (payload / "share/applications").mkdir(parents=True)
            (payload / f"share/applications/{app}.desktop").write_text(
                f"[Desktop Entry]\nType=Application\nName={app}\nExec=fixture\n")
            command(env, "flatpak", "build-export", str(root / "repo"), str(build), "stable")
        command(env, "flatpak", "build-update-repo", str(root / "repo"))
        if version == 1:
            command(env, "flatpak", "remote-add", "--user", "--no-gpg-verify", "fixture", str(root / "repo"))
            command(env, "flatpak", "install", "--user", "--noninteractive", "--no-related", "fixture", *apps)
    before = {ref: commit(env, ref) for ref in apps + ["runtime/" + runtime]}
    requests = []

    class Repository(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            requests.append(self.path)
            time.sleep(0.05)  # Controlled metadata latency, not a real WAN benchmark.
            super().do_GET()

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0),
        lambda *a, **kw: Repository(*a, directory=str(root / "repo"), **kw))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    command(env, "flatpak", "remote-modify", "--user", "--url=" + f"http://127.0.0.1:{server.server_port}", "fixture")
    shutil.copytree(root / "user", root / "initial-user", symlinks=True)

    def scan(binary, label):
        # Restore the same installed commits, AppStream and OSTree objects so
        # the candidate cannot benefit from metadata pulled by the baseline.
        shutil.rmtree(root / "user")
        shutil.copytree(root / "initial-user", root / "user", symlinks=True)
        shutil.rmtree(root / "user/repo/tmp/cache", ignore_errors=True)
        requests.clear()
        started = time.monotonic()
        with (root / (label + ".log")).open("w+") as log:
            child = subprocess.Popen([binary, "--updates-worker", '{"userOnly":true}'],
                                     env=env, stdout=subprocess.PIPE, stderr=log, text=True)
            peak_rss = 0
            lines = []
            with selectors.DefaultSelector() as watcher:
                watcher.register(child.stdout, selectors.EVENT_READ)
                while child.poll() is None:
                    try:
                        status = Path(f"/proc/{child.pid}/status").read_text()
                        peak_rss = max(peak_rss, int(next(l for l in status.splitlines() if l.startswith("VmRSS:")).split()[1]))
                    except (OSError, StopIteration):
                        pass
                    if time.monotonic() - started > 180:
                        child.kill()
                        raise AssertionError("Scan exceeded deadline")
                    if watcher.select(0.02):
                        lines.append(child.stdout.readline())
            output = "".join(lines) + child.stdout.read()
            log.seek(0)
            diagnostics = log.read()
        assert child.returncode == 0, diagnostics[-5000:]
        rows = json.loads(output.splitlines()[-1])
        assert rows["type"] == "updates" and not rows["errors"] and not rows["skipped"], rows
        assert len(rows["updates"]) == app_count + 1, {"count":len(rows["updates"]),"ids":[r["id"] for r in rows["updates"]]}
        for row in rows["updates"]:
            assert row["plan"] and row["downloadBytes"] > 0 and row["commit"]
            if not row["runtime"]:
                assert row["oldVersion"] == "1.0" and row["newVersion"] == "2.0", row
                index = int(row["id"][-2:])
                assert row["permissions"]["state"] == ("changed" if index % 2 == 0 else "unchanged"), row
        print(json.dumps(dict(label=label, seconds=time.monotonic()-started, peakWorkerRssKiB=peak_rss,
                              metadataRequests=len(requests), updates=len(rows["updates"]))))
        return {row["key"]: row for row in rows["updates"]}

    try:
        for round in range(3):
            old = scan(baseline, "baseline-" + str(round + 1))
            new = scan(candidate, "candidate-" + str(round + 1))
            assert old == new, "The faster scan changed prepared row data"
        # The same URL with different source policy must not share a result.
        # This is still only the fixture's private installation and app data.
        command(env, "flatpak", "remote-add", "--user", "--no-gpg-verify", "split-source",
                f"http://127.0.0.1:{server.server_port}")
        command(env, "flatpak", "remote-modify", "--user", "--no-use-for-deps", "split-source")
        command(env, "flatpak", "install", "--user", "--reinstall", "--noninteractive", "--no-related", "split-source", apps[-1])
        command(env, "flatpak", "update", "--user", "--noninteractive", "--no-deps", "--no-related",
                "--commit=" + before[apps[-1]], apps[-1])
        command(env, "flatpak", "update", "--user", "--noninteractive", "--no-deps", "--no-related",
                "--commit=" + before["runtime/" + runtime], "runtime/" + runtime)
        shutil.rmtree(root / "initial-user")
        shutil.copytree(root / "user", root / "initial-user", symlinks=True)
        old = scan(baseline, "baseline-distinct-source-policy")
        new = scan(candidate, "candidate-distinct-source-policy")
        assert old == new, "A different source policy changed the prepared rows"
        stages = [json.loads(line.split(" ", 1)[1]) for line in
                  (root / "candidate-distinct-source-policy.log").read_text().splitlines()
                  if line.startswith("APPCENTER_SCAN_TIMING ")]
        assert sum(row["stage"] == "appstream" for row in stages) == 2, "Different source policy reused metadata"
        assert before == {ref: commit(env, ref) for ref in before}, "Scanning deployed an update"
        assert set(command(env, "flatpak", "remotes", "--user", "--columns=name").splitlines()) == {"fixture", "split-source"}
        print(f"PASS: all {app_count + 1} complete rows match, including versions, sizes, source identity, exact plans and permission diffs; no deployment")
        print("PASS: matching URL with different source policy is refreshed independently")
    finally:
        server.shutdown()
        server.server_close()
