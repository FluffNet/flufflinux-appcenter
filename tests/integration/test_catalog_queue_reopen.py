"""Real installed/rebuilt binary: background installs must preserve a fresh cache.

Uses two tiny local Flatpaks, private installation/config/cache/socket paths and
a controlled slow catalog worker to reproduce the shutdown race. Never replaces
App Center or changes the user's apps/sources. Run inside the KDE session.
"""
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

binary = str(Path(sys.argv[1]).resolve())
reopen_during_save = "--reopen-during-save" in sys.argv
scripts = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="appcenter-queue-cache-") as directory:
    root = Path(directory)
    for name in ("runtime", "config", "flatpak-config"):
        (root / name).mkdir(mode=0o700)
    (root / "config/flufflinux-appcenter.conf").write_text("[Sources]\ninitialized=true\n")
    env = dict(os.environ, XDG_RUNTIME_DIR=str(root / "runtime"), WAYLAND_DISPLAY="/run/user/1000/wayland-0",
               XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
               XDG_CACHE_HOME=str(root / "cache"), APPCENTER_TEST_CACHE_HOME=str(root / "cache"),
               FLATPAK_USER_DIR=str(root / "user"), FLATPAK_SYSTEM_DIR=str(root / "system"),
               FLATPAK_CONFIG_DIR=str(root / "flatpak-config"), QT_FORCE_STDERR_LOGGING="1",
               FLUFF_APP_CENTER_CATALOG_TEST="1", QT_QUICK_BACKEND="software")

    def run(*args):
        result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=90)
        assert result.returncode == 0, (args, result.stdout, result.stderr)
        return result.stdout

    arch = run("flatpak", "--default-arch").strip()
    runtime = "org.example.QueueCache.Runtime"
    apps = ["org.example.QueueCache.App1", "org.example.QueueCache.App2"]
    for app in [runtime, *apps]:
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
        if not is_runtime:
            (payload / "share/metainfo").mkdir(parents=True)
            (payload / "share/applications").mkdir(parents=True)
            metadata = f'''<component type="desktop-application"><id>{app}</id><name>{app}</name>
<summary>Queue cache regression test</summary><metadata_license>CC0-1.0</metadata_license>
<project_license>MIT</project_license><description><p>Isolated test app.</p></description>
<launchable type="desktop-id">{app}.desktop</launchable></component>'''
            (payload / f"share/metainfo/{app}.metainfo.xml").write_text(metadata)
            (payload / f"share/applications/{app}.desktop").write_text(
                f"[Desktop Entry]\nType=Application\nName={app}\nExec=fixture\n")
            (payload / "share/app-info/xmls").mkdir(parents=True)
            (payload / f"share/app-info/xmls/{app}.xml.gz").write_bytes(
                gzip.compress(("<components>" + metadata + "</components>").encode()))
        run("flatpak", "build-export", *(["--runtime"] if is_runtime else []), str(root / "repo"), str(build), "stable")
    run("flatpak", "build-update-repo", str(root / "repo"))
    run("flatpak", "remote-add", "--user", "--no-gpg-verify", "queue-cache", str(root / "repo"))
    run("flatpak", "install", "--user", "--noninteractive", "--no-related", "queue-cache", runtime)

    def launch(label):
        output = run(sys.executable, str(scripts / "benchmark_startup.py"), binary)
        print(label + "\n" + output, flush=True)
        return output

    launch("COLD")
    cache, = (root / "cache").rglob("application-list.json")
    original = json.loads(cache.read_text())
    # An old-but-valid refresh timestamp makes accidental lifetime extension visible.
    original["savedAt"] = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    if "checksum" in original:
        original["checksum"] = hashlib.sha256(json.dumps({k: v for k, v in original.items() if k != "checksum"},
            sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
    cache.write_text(json.dumps(original))
    assert "catalog-cache-ready" in launch("WARM BEFORE QUEUE")
    qml = root / "Queue.qml"
    assets = Path("/usr/share/flufflinux-appcenter/qml") if binary == "/usr/bin/flufflinux-appcenter" else scripts.parents[1] / "qml"
    qml.write_text((scripts / "CatalogQueueSmoke.qml").read_text().replace('"../../qml"', json.dumps(assets.as_uri())))
    queue_env = dict(env, FLUFF_APP_CENTER_QML=str(qml), FLUFF_APP_CENTER_BACKGROUND_TEST="1")
    with (root / "queue.log").open("w+") as log:
        process = subprocess.Popen([binary], env=queue_env, stdout=log, stderr=subprocess.STDOUT)
        stopped = set()
        paused_at = None
        resumed = False
        reopened_while_paused = False
        try:
            deadline = time.monotonic() + 45
            while process.poll() is None and time.monotonic() < deadline:
                children = Path(f"/proc/{process.pid}/task/{process.pid}/children")
                for pid in children.read_text().split() if children.exists() else []:
                    try:
                        args = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
                        if b"--catalog" in args and paused_at is None:
                            os.kill(int(pid), signal.SIGSTOP)
                            stopped.add(int(pid)); paused_at = time.monotonic()
                            print("Paused the post-install local catalog worker for 4 seconds", pid, flush=True)
                    except ProcessLookupError:
                        pass
                    except FileNotFoundError:
                        pass
                if reopen_during_save and paused_at and not reopened_while_paused:
                    log.flush()
                    if "QUEUE_CACHE_COMPLETE" in (root / "queue.log").read_text():
                        activated_at = time.monotonic()
                        activation = subprocess.run([binary], env=queue_env, capture_output=True, timeout=3)
                        elapsed = time.monotonic() - activated_at
                        assert activation.returncode == 0 and elapsed < 2, (activation.stderr, elapsed)
                        assert process.poll() is None, "The original process must handle reopening"
                        reopened_while_paused = True
                        print(f"REOPEN_WHILE_SAVING_SECONDS={elapsed:.3f}, original PID={process.pid}", flush=True)
                if paused_at and not resumed and time.monotonic() - paused_at >= 4:
                    if reopen_during_save:
                        visible_log = (root / "queue.log").read_text()
                        assert reopened_while_paused, "The window was not reopened during the save"
                        assert "QUEUE_CACHE_REOPEN_FRAME apps 2 loaded true emptyMessage false" in visible_log, visible_log
                        assert "QUEUE_CACHE_CLOSED_AGAIN" in visible_log, visible_log
                    for pid in stopped:
                        try:
                            os.kill(pid, signal.SIGCONT)
                        except ProcessLookupError:
                            pass
                    resumed = True
                time.sleep(.01)
            process.wait(timeout=2)
            print("QUEUE_EXIT", process.returncode, "after pause", time.monotonic() - paused_at if paused_at else None,
                  "resumed", resumed, flush=True)
        finally:
            for pid in stopped:
                try:
                    os.kill(pid, signal.SIGCONT)
                except ProcessLookupError:
                    pass
            if process.poll() is None:
                process.terminate(); process.wait(timeout=10)
        log.seek(0)
        output = log.read()
        print(output, flush=True)
        assert process.returncode == 0 and "QUEUE_CACHE_COMPLETE" in output and paused_at is not None, output
    installed = run("flatpak", "list", "--user", "--app", "--columns=application").splitlines()
    assert set(installed) == set(apps), installed
    updated = json.loads(cache.read_text())
    reopened = launch("REOPEN AFTER COMPLETED QUEUE")
    assert "catalog-cache-ready" in reopened, "BUG: a completed background queue invalidated the fresh startup cache"
    assert updated["savedAt"] == original["savedAt"], "Local rebuild extended source-refresh lifetime"
    assert updated["fingerprint"] != original["fingerprint"], "New installation state was not saved"
    print("PASS: real background installs, delayed local parser survives shutdown, immediate cached reopen, original 12-hour deadline preserved")
    if reopen_during_save:
        print("PASS: reopening during the save reuses the original process and visible app list; closing again allows the same save to finish")
