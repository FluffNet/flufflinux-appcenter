#!/usr/bin/env python3
"""Real add-on transactions in an isolated Flatpak installation only."""
import gzip
import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time
from test_updates import environment, command, BINARY

APP = "org.flufflinux.AddonFixture"
ADDON = APP + ".Plugin.Example"
RUNTIME = "org.flufflinux.AddonFixtureRuntime"


def transaction(env, request, approve=False):
    events = []
    child = subprocess.Popen([BINARY, "--transaction-worker", json.dumps(request)], env=env,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    watcher = selectors.DefaultSelector()
    watcher.register(child.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + 60
    try:
        while time.monotonic() < deadline:
            if not watcher.select(1):
                continue
            line = child.stdout.readline()
            assert line, child.stderr.read().decode()
            event = json.loads(line)
            events.append(event)
            if event["type"] == "review":
                assert request["action"] == "uninstall", event
                child.stdin.write((json.dumps({"token": event["token"], "accept": approve}) + "\n").encode())
                child.stdin.flush()
            if event["type"] == "result":
                child.stdin.close(); child.wait(timeout=10)
                return event, events
        raise AssertionError("Add-on worker timed out")
    finally:
        watcher.close()
        if child.poll() is None:
            child.kill(); child.wait(timeout=5)


def fixture(root):
    env = environment(root)
    (root / "config").mkdir()
    arch = command(env, "flatpak", "--default-arch")
    runtime = f"{RUNTIME}/{arch}/stable"
    parent_ref = f"app/{APP}/{arch}/stable"
    addon_ref = f"runtime/{ADDON}/{arch}/stable"
    for identity, branch in [(RUNTIME, "stable"), (APP, "stable"), (ADDON, "stable"), (ADDON, "incompatible")]:
        is_app = identity == APP
        is_addon = identity == ADDON
        build = root / (identity + "-" + branch)
        payload = build / ("files" if is_app or is_addon else "usr")
        (payload / "bin").mkdir(parents=True)
        (build / "files").mkdir(exist_ok=True)
        (build / "export").mkdir()
        metadata = f'[{"Application" if is_app else "Runtime"}]\nname={identity}\nruntime={runtime}\nsdk={runtime}\n'
        if is_app:
            metadata += f"command=fixture\n[Extension {APP}.Plugin]\ndirectory=plugins\nsubdirectories=true\nversion=stable\nno-autodownload=true\nautodelete=true\n"
            (payload / "plugins").mkdir()
        if is_addon:
            metadata += f"[ExtensionOf]\nref={parent_ref}\n"
        (build / "metadata").write_text(metadata)
        (payload / "bin/fixture").write_text("#!/bin/sh\nexit 0\n")
        (payload / "bin/fixture").chmod(0o755)
        if is_app or is_addon:
            component = f'''<component type="{'addon' if is_addon else 'desktop-application'}">
<id>{identity}</id><name>{'Example Plugin' if is_addon else 'Add-On Test App'}</name>
<summary>Isolated add-on integration fixture</summary><metadata_license>CC0-1.0</metadata_license>
<project_license>MIT</project_license><description><p>Real isolated add-on test.</p></description>
<releases><release version="1.0" date="2026-09-27"/></releases>
{'<extends>' + APP + '</extends>' if is_addon else '<launchable type="desktop-id">' + APP + '.desktop</launchable>'}
</component>'''
            info = payload / "share/app-info/xmls"
            info.mkdir(parents=True)
            with gzip.open(info / (identity + ".xml.gz"), "wb") as output:
                output.write(("<components>" + component + "</components>").encode())
        command(env, "flatpak", "build-export", *([] if is_app else ["--runtime"]), str(root / "repo"), str(build), branch)
    command(env, "flatpak", "build-update-repo", str(root / "repo"))
    command(env, "flatpak", "remote-add", "--user", "--no-gpg-verify", "addons-fixture", str(root / "repo"))
    command(env, "flatpak", "install", "--user", "--noninteractive", "--no-related", "addons-fixture", "runtime/" + runtime, parent_ref)
    command(env, "flatpak", "update", "--user", "--appstream", "addons-fixture")
    catalog = json.loads(command(env, str(BINARY), "--catalog"))
    parent = next(app for app in catalog if app["id"] == APP)
    assert all(app["id"] != ADDON for app in catalog), "Add-ons leaked into the main app catalog"
    assert parent["addons"] and all(row["id"] == ADDON for row in parent["addons"]), parent
    parent.update(installation="user", installedRef=parent_ref, installedArch=arch, installedBranch="stable")
    (root / "parent.json").write_text(json.dumps(parent))
    return env, parent, addon_ref


def test(root):
    env, parent, addon_ref = fixture(root)
    def read():
        return json.loads(command(env, str(BINARY), "--addons-worker", json.dumps(parent)))
    view = read()
    assert view["state"] == "ready" and len(view["items"]) == 1, view
    row = view["items"][0]
    assert row["flatpakRef"] == addon_ref and row["available"] and not row["installed"], row
    request = dict(row, action="install", parent=view["parent"])
    original_commit = command(env, "flatpak", "info", "--user", "--show-commit", parent["installedRef"])
    # A substituted runtime, branch, installation or stale parent cannot deploy.
    for invalid in [dict(request, flatpakRef=f"runtime/{RUNTIME}/{parent['installedArch']}/stable"),
                    dict(request, flatpakRef=addon_ref.replace("/stable", "/incompatible")),
                    dict(request, installation="system"),
                    dict(request, parent=dict(view["parent"], parentCommit="0" * 64))]:
        result, _ = transaction(env, invalid)
        assert not result["success"], result
    result, _ = transaction(env, request)
    assert result["success"], result
    view = read()
    assert view["items"][0]["installed"], view
    request = dict(view["items"][0], action="uninstall", parent=view["parent"])
    result, _ = transaction(env, request, approve=False)
    assert not result["success"] and read()["items"][0]["installed"]
    result, events = transaction(env, request, approve=True)
    assert result["success"] and not read()["items"][0]["installed"], (result, events)
    assert not any("Deleting sandbox data" in event.get("status", "") for event in events)
    assert command(env, "flatpak", "info", "--user", "--show-commit", parent["installedRef"]) == original_commit
    assert command(env, "flatpak", "info", "--user", "--show-ref", "runtime/" + RUNTIME).startswith("runtime/")
    print("PASS: catalog add-ons, exact installed-parent compatibility, wrong ref/branch/scope/stale rejection, install, declined removal, confirmed removal, parent/runtime preserved", flush=True)


if __name__ == "__main__":
    root = Path(tempfile.mkdtemp(prefix="appcenter-addons-"))
    print("FIXTURE", root, flush=True)
    test(root)
