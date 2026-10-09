#!/usr/bin/env python3
"""Resolve downloaded references and test tiny bundles in disposable installations.

python3 tests/integration/test_local_preview.py [--live]
The optional live case downloads a public Flathub reference but never installs
that app. All source registration, test installs and caches are temporary.
"""
import argparse
import base64
import gzip
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "target/debug/flufflinux-appcenter"


def transaction(env, request, approve=True):
    events = []
    with subprocess.Popen([str(BINARY), "--transaction-worker", json.dumps(request)],
                          env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0) as child:
        selector = selectors.DefaultSelector()
        selector.register(child.stdout, selectors.EVENT_READ)
        try:
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                if not selector.select(1):
                    continue
                line = child.stdout.readline()
                assert line, "Preview worker ended without a result"
                event = json.loads(line)
                events.append(event)
                if event["type"] == "review":
                    child.stdin.write((json.dumps(dict(token=event["token"], accept=approve)) + "\n").encode())
                    child.stdin.flush()
                if event["type"] == "result":
                    child.stdin.close()
                    child.wait(timeout=10)
                    return events
            raise AssertionError("Local-file transaction exceeded its time limit")
        finally:
            selector.close()
            if child.poll() is None:
                child.kill()
                child.wait(timeout=10)


def prepare(env, path, approve=True):
    before = command(env, "flatpak", "remotes", "--user", "--show-details")
    events = transaction(env, dict(action="source", source=path.as_uri(), prepareOnly=True), approve)
    assert not any(e["type"] in ("review", "operation") for e in events), events
    assert command(env, "flatpak", "remotes", "--user", "--show-details") == before, "Preview changed configured sources"
    return events


def command(env, *args):
    return subprocess.check_output(args, env=env, text=True, timeout=60)


def screenshots(env, root, path):
    runtime_dir = root / "runtime"
    runtime_dir.mkdir(mode=0o700)
    ui_env = dict(env, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                  QT_FORCE_STDERR_LOGGING="1", QT_QPA_PLATFORMTHEME="kde", XDG_RUNTIME_DIR=str(runtime_dir),
                  FLUFF_APP_CENTER_QML=str(ROOT / "tests/fixtures/LocalPreviewSmoke.qml"))
    remotes = command(env, "flatpak", "remotes", "--user", "--show-details")
    subprocess.run([str(BINARY), str(path)], env=ui_env, check=True, timeout=120)
    after = command(env, "flatpak", "remotes", "--user", "--show-details")
    assert after == remotes, (remotes, after)
    assert not command(env, "flatpak", "list", "--user", "--columns=ref").strip()


def bundle_test(env, root):
    arch = command(env, "flatpak", "--default-arch").strip()
    identity = "org.flufflinux.LocalPreview"
    runtime = f"org.flufflinux.LocalPreviewRuntime/{arch}/stable"
    for is_runtime in [True, False]:
        app_id = runtime.split("/")[0] if is_runtime else identity
        build = root / app_id
        payload = build / ("usr" if is_runtime else "files")
        (payload / "bin").mkdir(parents=True)
        (build / "files").mkdir(exist_ok=True)
        (build / "export").mkdir()
        metadata = f'[{"Runtime" if is_runtime else "Application"}]\nname={app_id}\nruntime={runtime}\nsdk={runtime}\n'
        if not is_runtime:
            metadata += "command=fixture\n[Context]\nshared=network;\nsockets=wayland;pulseaudio;\nfilesystems=xdg-download:ro;\n"
            xml = f'''<components><component type="desktop-application"><id>{identity}</id><name>Local Bundle Preview</name>
<summary>Offline preview fixture</summary><metadata_license>CC0-1.0</metadata_license><project_license>MIT</project_license>
<description><p>Details embedded in the bundle, without a catalog.</p></description>
<developer_name>Fixture Publisher</developer_name><categories><category>AudioVideo</category></categories>
<screenshots><screenshot><image type="source">https://example.org/preview.png</image></screenshot></screenshots>
<bundle type="flatpak">app/{identity}/{arch}/stable</bundle></component></components>'''
            info = payload / "share/app-info/xmls"
            info.mkdir(parents=True)
            (info / (identity + ".xml.gz")).write_bytes(gzip.compress(xml.encode()))
            for size in (64, 128):
                icons = payload / f"share/app-info/icons/flatpak/{size}x{size}"
                icons.mkdir(parents=True)
                (icons / (identity + ".png")).write_bytes(base64.b64decode(
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        (build / "metadata").write_text(metadata)
        (payload / "bin/fixture").write_text("#!/bin/sh\nexit 0\n")
        (payload / "bin/fixture").chmod(0o755)
        command(env, "flatpak", "build-export", *(["--runtime"] if is_runtime else []), str(root / "repo"), str(build), "stable")
    command(env, "flatpak", "remote-add", "--user", "--no-gpg-verify", "fixture", str(root / "repo"))
    path = root / "fixture.flatpak"
    command(env, "flatpak", "build-bundle", "--repo-url=" + (root / "repo").as_uri(),
            str(root / "repo"), str(path), identity, "stable")
    cold_events = prepare(env, path)
    cold_plan = next(e for e in cold_events if e["type"] == "plan")
    assert cold_plan["state"] == "ready" and cold_plan["totalBytes"] > cold_plan["appBytes"], cold_plan
    cold_env = dict(env, FLATPAK_USER_DIR=str(root / "cold-user"))
    command(cold_env, "flatpak", "remote-add", "--user", "--no-gpg-verify", "fixture", str(root / "repo"))
    cold_install = transaction(cold_env, dict(action="source", source=path.as_uri(), id=identity,
                              sourceReviewed=True, sourceUrl=cold_plan["app"]["sourceUrl"],
                              flatpakRef=cold_plan["app"]["flatpakRef"]))
    assert cold_install[-1]["success"], cold_install
    actual = next(e for e in cold_install if e["type"] == "plan")
    assert actual["totalBytes"] == cold_plan["totalBytes"], (cold_plan, actual)
    command(env, "flatpak", "install", "--user", "--noninteractive", "--no-related", "fixture", "runtime/" + runtime)
    before = command(env, "flatpak", "list", "--user", "--columns=ref")
    events = prepare(env, path)
    assert events[-1]["success"], events[-1]
    assert not any(e["type"] == "operation" for e in events)
    plan = next(e for e in events if e["type"] == "plan")
    assert plan["app"]["name"] == "Local Bundle Preview", plan
    assert plan["app"]["description"] == "Details embedded in the bundle, without a catalog.", plan
    assert plan["app"]["screenshots"] == ["https://example.org/preview.png"], plan
    assert Path(plan["app"]["icon"]).is_file(), plan["app"]
    assert plan["permissions"]["state"] == "ready", plan
    assert plan["state"] == "ready" and plan["totalBytes"] == plan["appBytes"], plan
    print("PASS: preview total matches real installation and excludes an already-installed runtime", flush=True)
    assert {g["id"] for g in plan["permissions"]["groups"]} >= {"network", "audio", "display", "files"}
    declined = transaction(env, dict(action="source", source=path.as_uri(), id=identity), approve=False)
    assert declined[-1]["cancelled"] and not declined[-1]["success"]
    assert not any(e["type"] in ("plan", "operation") for e in declined)
    assert command(env, "flatpak", "list", "--user", "--columns=ref") == before
    print("PASS: offline bundle embeds details, icon, screenshots and permissions; preview/cancel do not install", flush=True)
    unavailable = root / "repo-unavailable"
    (root / "repo").rename(unavailable)
    try:
        offline = prepare(env, path)
        assert offline[-1]["success"], offline
        offline_plan = next(event for event in offline if event["type"] == "plan")
        assert offline_plan["permissions"]["state"] == "ready", offline_plan
        assert offline_plan["app"]["name"] == "Local Bundle Preview", offline_plan
        empty_env = dict(env, FLATPAK_USER_DIR=str(root / "empty-user"))
        empty = prepare(empty_env, path)
        assert empty[-1]["success"], empty
        empty_plan = next(event for event in empty if event["type"] == "plan")
        assert empty_plan["permissions"]["state"] == "ready", empty_plan
        assert empty_plan["state"] == "partial" and "totalBytes" not in empty_plan, empty_plan
        install = transaction(empty_env, dict(action="source", source=path.as_uri(), id=identity))
        assert not install[-1]["success"] and "runtime" in install[-1]["error"], install
        assert not command(empty_env, "flatpak", "list", "--user", "--columns=ref").strip()
    finally:
        unavailable.rename(root / "repo")
    print("PASS: bundle details and permissions remain readable with its source unavailable", flush=True)
    # A bundle uses Flatpak's app-specific origin. It must point at the embedded
    # source, be registered only during install, and receive normal updates.
    remotes = command(env, "flatpak", "remotes", "--user", "--columns=name,url")
    installed = transaction(env, dict(action="source", source=path.as_uri(), id=identity,
                                     sourceReviewed=True, sourceUrl=plan["app"]["sourceUrl"],
                                     flatpakRef=plan["app"]["flatpakRef"]))
    assert installed[-1]["success"], installed
    assert not any(event["type"] == "review" for event in installed), installed
    install_plan = next(event for event in installed if event["type"] == "plan")
    assert install_plan["totalBytes"] == plan["totalBytes"], (plan, install_plan)
    origin = command(env, "flatpak", "info", "--user", "--show-origin", identity).strip()
    after = command(env, "flatpak", "remotes", "--user", "--columns=name,url")
    assert f"{origin}\t{(root / 'repo').as_uri()}\n" in after, (origin, after)
    assert origin not in {line.split("\t")[0] for line in remotes.splitlines()}, (origin, remotes)
    prepare(env, path)
    assert command(env, "flatpak", "remotes", "--user", "--columns=name,url") == after
    old_commit = command(env, "flatpak", "info", "--user", "--show-commit", identity).strip()
    (root / identity / "files/bin/fixture").write_text("#!/bin/sh\n# New release from the source\nexit 0\n")
    command(env, "flatpak", "build-export", str(root / "repo"), str(root / identity), "stable")
    command(env, "flatpak", "build-update-repo", str(root / "repo"))
    scan = command(env, str(BINARY), "--updates-worker", '{"userOnly":true}')
    result = [json.loads(line) for line in scan.splitlines()][-1]
    assert not result["errors"], result
    update = next(item for item in result["updates"] if item["id"] == identity)
    assert update["remote"] == origin and update["oldCommit"] == old_commit, update
    updated = transaction(env, dict(update, action="update"))
    assert updated[-1]["success"], updated
    assert command(env, "flatpak", "info", "--user", "--show-commit", identity).strip() == update["commit"]
    assert update["commit"] != old_commit
    print("PASS: local bundle preserves its embedded source and receives a real App Center update", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--cached-metadata", action="store_true")
    parser.add_argument("--screenshots", action="store_true")
    parser.add_argument("--file", type=Path, help="Preview an existing downloaded reference in an isolated installation")
    parser.add_argument("--app", choices=["com.discordapp.Discord", "com.prusa3d.PrusaSlicer"], default="com.discordapp.Discord")
    args = parser.parse_args()
    identity = args.app
    assert os.geteuid() != 0, "Do not run as root"
    with tempfile.TemporaryDirectory(prefix="appcenter-local-preview-", dir="/tmp") as directory:
        root = Path(directory)
        env = dict(os.environ, FLATPAK_USER_DIR=str(root / "user"),
                   FLATPAK_SYSTEM_DIR=str(root / "system"), FLATPAK_CONFIG_DIR=str(root / "config"),
                   XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"),
                   XDG_CONFIG_HOME=str(root / "settings"))
        (root / "config").mkdir()
        if args.file:
            key_name = next(line.split("=", 1)[1].strip() for line in args.file.read_text().splitlines() if line.startswith("Name="))
            events = prepare(env, args.file.resolve())
            assert events[-1]["success"], events
            plan = next(event for event in events if event["type"] == "plan")
            assert plan["app"]["id"] == key_name, plan
            assert plan["app"]["description"] and plan["app"]["icon"], plan
            assert plan["permissions"]["state"] == "ready", plan
            assert plan["state"] == "ready" and plan["totalBytes"] > plan["appBytes"], plan
            (ROOT / "target/local-preview-downloaded.json").write_text(json.dumps(plan, indent=2))
            if args.screenshots:
                screenshots(env, root, args.file.resolve())
            # Do not resolve/download a real runtime while checking install consent.
            no_runtime = root / args.file.name
            no_runtime.write_text("\n".join(line for line in args.file.read_text().splitlines() if not line.startswith("RuntimeRepo=")) + "\n")
            install = transaction(env, dict(action="source", source=no_runtime.as_uri(), id=key_name), approve=False)
            assert any(event["type"] == "review" and event.get("kind") == "remote" for event in install), install
            assert install[-1]["cancelled"] and not install[-1]["success"], install
            assert not command(env, "flatpak", "remotes", "--user", "--columns=name").strip(), install
            assert not command(env, "flatpak", "list", "--user", "--columns=ref").strip()
            # Exercise the page's source consent without installing a real app.
            # Omit RuntimeRepo in a test copy so the empty installation cannot
            # resolve its runtime and must stop before download/deployment.
            reviewed = transaction(env, dict(action="source", source=no_runtime.as_uri(), id=key_name,
                                           sourceReviewed=True, sourceUrl=plan["app"]["sourceUrl"],
                                           flatpakRef=plan["app"]["flatpakRef"]))
            assert not any(event["type"] in ("review", "operation") for event in reviewed), reviewed
            assert not reviewed[-1]["success"] and "runtime" in reviewed[-1]["error"].lower(), reviewed
            assert plan["app"]["sourceUrl"] in command(env, "flatpak", "remotes", "--user", "--columns=url")
            assert not command(env, "flatpak", "list", "--user", "--columns=ref").strip()
            print("PASS: downloaded reference previews without adding sources; page consent adds its source only on install, without another prompt", flush=True)
            return
        if not args.live:
            bundle_test(env, root)
            return
        path = root / (identity + ".flatpakref")
        urllib.request.urlretrieve("https://dl.flathub.org/repo/appstream/" + identity + ".flatpakref", path)
        if args.cached_metadata:
            # Copy, never change, the test VM's genuine Flathub metadata to
            # cover the warm-source path separately from the fresh-network test.
            remotes = command(os.environ, "flatpak", "remotes", "--system", "--columns=name,url").splitlines()
            assert "flathub\thttps://dl.flathub.org/repo/" in remotes, remotes
            arch = command(env, "flatpak", "--default-arch").strip()
            cached = Path("/var/lib/flatpak/appstream/flathub") / arch / "active"
            shutil.copytree(cached, root / "user/appstream/flathub" / arch / "active")
        started = time.monotonic()
        events = prepare(env, path)
        print(f"Resolved preview in {time.monotonic() - started:.1f}s", flush=True)
        assert events[-1]["success"], events[-1]
        assert not any(e["type"] == "operation" for e in events), "Preview installed an app"
        plan = next(e for e in events if e["type"] == "plan")
        app = plan["app"]
        assert app["id"] == identity and app["name"] == identity.split(".")[-1], app
        assert app["description"] and app["screenshots"] and app["icon"] and app["license"], app
        assert app["sourceUrl"] == "https://dl.flathub.org/repo/", app
        assert app["flatpakRef"].startswith("app/" + identity + "/"), app
        assert plan["permissions"]["state"] == "ready", plan["permissions"]
        assert plan["state"] == "ready" and plan["totalBytes"] > plan["appBytes"], plan
        assert any(g["id"] == "network" for g in plan["permissions"]["groups"])
        remotes = command(env, "flatpak", "remotes", "--user", "--columns=name,url")
        assert not remotes.strip(), remotes
        repeated = prepare(env, path)
        assert repeated[-1]["success"], repeated
        assert command(env, "flatpak", "remotes", "--user", "--columns=name,url") == remotes
        assert not command(env, "flatpak", "list", "--user", "--columns=ref").strip()
        output = ROOT / ("target/local-preview-" + identity + ".json")
        output.write_text(json.dumps(plan, indent=2))
        mode = "cached-source" if args.cached_metadata else "fresh-source"
        print(f"PASS: {mode} {app['name']} reference has details, images, source and permissions; no app installed ({time.monotonic() - started:.1f}s)", flush=True)
        if args.screenshots:
            screenshots(env, root, path)


if __name__ == "__main__":
    main()
