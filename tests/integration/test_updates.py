#!/usr/bin/env python3
"""Repeatable offline update fixtures. No real app or installation is changed.

Run: python3 tests/integration/test_updates.py [--keep DIRECTORY]
Old/new commits and bundles remain in DIRECTORY when requested. Use --reset
DIRECTORY to restore ONLY that fixture's isolated user installation to v1.
"""
import argparse
import gzip
import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time

PROJECT = Path(__file__).resolve().parents[2]
BINARY = PROJECT / "target/release/flufflinux-appcenter"
IDS = ["org.flufflinux.UpdateFixtureAlpha", "org.flufflinux.UpdateFixtureBeta"]
RUNTIME = "org.flufflinux.UpdateFixtureRuntime"


def environment(root):
    return dict(os.environ, FLATPAK_USER_DIR=str(root / "user"), FLATPAK_SYSTEM_DIR=str(root / "system"),
                FLATPAK_CONFIG_DIR=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
                XDG_CACHE_HOME=str(root / "cache"), XDG_CONFIG_HOME=str(root / "settings"))


def command(env, *args):
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    return result.stdout.strip()


def worker(env, request, cancel=False):
    events = []
    child = subprocess.Popen([str(BINARY), "--transaction-worker", json.dumps(request)],
                             env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    watcher = selectors.DefaultSelector()
    watcher.register(child.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + 60
    try:
        if cancel:
            child.stdin.write(b'{"cancel":true}\n'); child.stdin.flush()
        while time.monotonic() < deadline:
            if not watcher.select(1):
                continue
            line = child.stdout.readline()
            assert line, child.stderr.read().decode()
            event = json.loads(line)
            events.append(event)
            assert event["type"] != "review", "Updates must not create/add a source"
            if event["type"] == "result":
                child.stdin.close(); child.wait(timeout=10)
                return events
        raise AssertionError("Update worker timed out")
    finally:
        watcher.close()
        if child.poll() is None:
            child.kill(); child.wait()


def scan(env):
    output = command(env, str(BINARY), "--updates-worker", '{"userOnly":true}')
    event = [json.loads(line) for line in output.splitlines()][-1]
    assert event["type"] == "updates", event
    assert not event["errors"], event
    return event["updates"]


def commit(env, ref):
    return command(env, "flatpak", "info", "--user", "--show-commit", ref)


def reset(root):
    manifest = json.loads((root / "manifest.json").read_text())
    assert manifest["fixture"] == "appcenter-updates-v1"
    assert set(manifest["apps"]) == set(IDS)
    assert root.is_absolute() and (root / "user/repo").is_dir()
    env = environment(root)
    for ref, revision in manifest["old"].items():
        assert ref.split("/")[1] in IDS + [RUNTIME]
        command(env, "flatpak", "update", "--user", "--noninteractive", "--no-deps", "--no-related",
                "--commit=" + revision, ref)
        assert commit(env, ref) == revision
    print("Restored isolated test apps to v1:", root, flush=True)


def test(root):
    env = environment(root)
    (root / "config").mkdir()
    arch = command(env, "flatpak", "--default-arch")
    runtime = f"{RUNTIME}/{arch}/stable"
    refs = [f"app/{app}/{arch}/stable" for app in IDS]
    runtime_ref = "runtime/" + runtime
    old = {}
    for version in (1, 2):
        for app in [RUNTIME] + IDS:
            is_runtime = app == RUNTIME
            build = root / f"build-{app}-v{version}"
            payload = build / ("usr" if is_runtime else "files")
            (payload / "bin").mkdir(parents=True)
            (build / "files").mkdir(exist_ok=True)
            (build / "export").mkdir()
            metadata = f'[{"Runtime" if is_runtime else "Application"}]\nname={app}\nruntime={runtime}\nsdk={runtime}\n'
            if not is_runtime:
                metadata += "command=fixture\n[Context]\nsockets=wayland;\n"
                if version == 2 and app == IDS[0]:
                    metadata += "shared=network;\nfilesystems=xdg-download:ro;\n"
                metainfo = payload / "share/metainfo"
                metainfo.mkdir(parents=True)
                (metainfo / (app + ".metainfo.xml")).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application"><id>{app}</id><name>Update Fixture {app.split('.')[-1]}</name>
<summary>Offline App Center update test</summary><metadata_license>CC0-1.0</metadata_license>
<project_license>MIT</project_license><description><p>An isolated update test fixture.</p></description>
<releases><release version="{version}.0" date="2026-09-0{version}"/></releases>
<content_rating type="oars-1.1"/><launchable type="desktop-id">{app}.desktop</launchable></component>''')
                appinfo = payload / "share/app-info/xmls"
                appinfo.mkdir(parents=True)
                component = (metainfo / (app + ".metainfo.xml")).read_text().split("?>", 1)[1]
                with gzip.open(appinfo / (app + ".xml.gz"), "wb") as info:
                    info.write(("<components>" + component + "</components>").encode())
                desktop = payload / "share/applications"
                desktop.mkdir(parents=True)
                (desktop / (app + ".desktop")).write_text(f"[Desktop Entry]\nType=Application\nName=Update Test\nExec=fixture\n")
            (build / "metadata").write_text(metadata)
            (payload / "bin/fixture").write_text(f"#!/bin/sh\n# Test version {version}\nexit 0\n")
            (payload / "bin/fixture").chmod(0o755)
            command(env, "flatpak", "build-export", *(["--runtime"] if is_runtime else []), str(root / "repo"), str(build), "stable")
            command(env, "flatpak", "build-bundle", *(["--runtime"] if is_runtime else []),
                    str(root / "repo"), str(root / f"{app}-v{version}.flatpak"), app, "stable")
        command(env, "flatpak", "build-update-repo", str(root / "repo"))
        if version == 1:
            command(env, "flatpak", "remote-add", "--user", "--no-gpg-verify", "update-fixture", str(root / "repo"))
            command(env, "flatpak", "install", "--user", "--noninteractive", "--no-related", "update-fixture", runtime_ref, *refs)
            old = {ref: commit(env, ref) for ref in refs + [runtime_ref]}
    manifest = {"fixture": "appcenter-updates-v1", "apps": IDS, "old": old, "root": str(root)}
    (root / "manifest.json").write_text(json.dumps(manifest, indent=2))
    before = {ref: commit(env, ref) for ref in old}
    rows = scan(env)
    assert {r["flatpakRef"] for r in rows} == set(old), rows
    assert before == {ref: commit(env, ref) for ref in old}, "Checking silently deployed updates"
    assert all(row["selected"] and row["downloadBytes"] > 0 and row["plan"] for row in rows)
    apps = {row["id"]: row for row in rows}
    assert apps[IDS[0]]["permissions"]["state"] == "changed", rows
    assert apps[IDS[1]]["permissions"]["state"] == "unchanged", rows
    assert apps[IDS[0]]["oldVersion"] == "1.0" and apps[IDS[0]]["newVersion"] == "2.0", rows
    request = dict(apps[IDS[0]], action="update")
    cancelled = worker(env, request, cancel=True)
    assert not cancelled[-1]["success"] and commit(env, refs[0]) == old[refs[0]]
    changed_source = dict(request, plan=[dict(op, sourceUrl="file:///wrong-source") for op in request["plan"]])
    assert not worker(env, changed_source)[-1]["success"]
    changed_commit = dict(request, plan=[dict(op, commit="0" * 64) for op in request["plan"]])
    assert not worker(env, changed_commit)[-1]["success"]
    assert {ref: commit(env, ref) for ref in old} == before
    first = worker(env, request)
    assert first[-1]["success"], first
    assert any(event["type"] == "updated" and event["historySaved"] for event in first), first
    assert commit(env, refs[0]) == request["commit"]
    assert commit(env, refs[1]) == old[refs[1]], "An unselected app was updated"
    history_files = list((root / "data").rglob("update-dates.json"))
    assert len(history_files) == 1, history_files
    history_before = history_files[0].read_text()
    noop = worker(env, request)
    assert noop[-1]["success"] and not any(e["type"] == "updated" for e in noop)
    assert history_files[0].read_text() == history_before, "No-op changed last-update date"
    second = worker(env, dict(apps[IDS[1]], action="update"))
    assert second[-1]["success"], second
    runtime_update = worker(env, dict(apps[RUNTIME], action="update"))
    assert runtime_update[-1]["success"], runtime_update
    assert scan(env) == [], "Completed updates still offered"
    history = json.loads(history_files[0].read_text())["installations"]
    assert set(history) == {"user:" + ref for ref in refs}, history
    reset(root)
    assert len(scan(env)) == 3, "The preserved older releases cannot be retested"
    command(env, "flatpak", "remote-modify", "--user", "--disable", "update-fixture")
    assert not worker(env, request)[-1]["success"], "Disabled source was used for updating"
    command(env, "flatpak", "remote-modify", "--user", "--enable", "update-fixture")
    command(env, "flatpak", "remote-modify", "--user", "--url=" + (root / "offline-repo").as_uri(), "update-fixture")
    try:
        offline = json.loads(command(env, str(BINARY), "--updates-worker", '{"userOnly":true}').splitlines()[-1])
        assert offline["errors"], "Offline source was reported as up-to-date"
    finally:
        command(env, "flatpak", "remote-modify", "--user", "--url=" + (root / "repo").as_uri(), "update-fixture")
    assert len(scan(env)) == 3
    print("PASS: manual metadata-only scan, versions, sizes, permission diff, cancel, stale source/plan, selected apps only, shared runtime, persistent dates, no-op, empty scan, v1 restore, disabled/offline sources", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--keep", type=Path)
    parser.add_argument("--reset", type=Path)
    args = parser.parse_args()
    assert os.geteuid() != 0, "Run as an ordinary user"
    if args.reset:
        reset(args.reset.resolve())
    elif args.keep:
        root = args.keep.resolve(); root.mkdir(parents=True, exist_ok=False)
        try:
            test(root)
        finally:
            print("Preserved test releases and bundles:", root, flush=True)
    else:
        with tempfile.TemporaryDirectory(prefix="appcenter-update-test-") as directory:
            test(Path(directory))
