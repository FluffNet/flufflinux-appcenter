#!/usr/bin/env python3
"""Repository-only tests in temporary Flatpak installations; never installs apps.

Run with target/test-source-worker and a public signing-key ring as arguments.
--online additionally verifies first-run official Flathub setup (metadata only).
"""
import base64
import gzip
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time

WORKER = str(Path(sys.argv[1]).resolve())
KEY = Path(sys.argv[2]).read_bytes()


def worker(env, request, approve=False):
    child = subprocess.Popen([WORKER, json.dumps(request)], env=env, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    events = []
    selector = selectors.DefaultSelector()
    selector.register(child.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + 180
    try:
        while time.monotonic() < deadline:
            if not selector.select(1):
                assert child.poll() is None, child.stderr.read().decode()
                continue
            line = child.stdout.readline()
            assert line, child.stderr.read().decode()
            event = json.loads(line)
            events.append(event)
            if event["type"] == "review":
                child.stdin.write((json.dumps({"token": event["token"], "accept": approve}) + "\n").encode())
            if event["type"] == "result":
                child.stdin.close()
                child.wait(10)
                return events
        raise AssertionError("Source worker timed out")
    finally:
        selector.close()
        if child.poll() is None:
            child.kill()
            child.wait()


def run(env, operation, **fields):
    events = worker(env, dict(action="repositories", operation=operation, **fields))
    assert not any(event["type"] == "review" for event in events), events
    assert events[-1]["success"], events
    return next(event["sources"] for event in events if event["type"] == "sources")


def isolated(root, create=True):
    env = os.environ.copy()
    # Flatpak's supported installation overrides; HOME is never changed.
    env.update(FLATPAK_USER_DIR=str(root / "user"), FLATPAK_SYSTEM_DIR=str(root / "system"),
               FLATPAK_CONFIG_DIR=str(root / "flatpak-config"), XDG_DATA_HOME=str(root / "data"),
               XDG_CACHE_HOME=str(root / "cache"), APPCENTER_TEST_CONFIG=str(root / "appcenter.conf"))
    (root / "flatpak-config").mkdir()
    for installation in (("user", "system") if create else ()):
        repo = root / installation / "repo"
        repo.parent.mkdir(parents=True)
        subprocess.run(["ostree", "--repo=" + str(repo), "init", "--mode=bare-user-only"], env=env, check=True)
    return env


def add_system(root, name, url, disabled=False):
    config = root / "system/repo/config"
    with config.open("a") as output:
        output.write(f'\n[remote "{name}"]\nurl={url}\ngpg-verify=true\ngpg-verify-summary=true\nxa.disable={str(disabled).lower()}\nxa.title={name}\nxa.nodeps=true\n')
    (root / f"system/repo/{name}.trustedkeys.gpg").write_bytes(KEY)
    # Synthetic cached catalog prevents network access in offline tests.
    arch = subprocess.check_output(["flatpak", "--default-arch"], text=True).strip()
    active = root / f"user/appstream/{name}/{arch}/active"
    active.mkdir(parents=True)
    (active / "appstream.xml.gz").write_bytes(gzip.compress(b"<components/>"))


with tempfile.TemporaryDirectory(prefix="appcenter-sources-") as directory:
    root = Path(directory)
    env = isolated(root)
    add_system(root, "flathub", "https://dl.flathub.org/repo/")
    add_system(root, "flathub-beta", "https://dl.flathub.org/beta-repo/")
    add_system(root, "vendor", "https://example.org/repo/", disabled=True)
    system_before = (root / "system/repo/config").read_bytes()
    sources = run(env, "initialize")
    users = {source["name"]: source for source in sources if source["scope"] == "user"}
    assert set(users) == {"flathub", "flathub-beta", "vendor"}, users
    assert all(source["verified"] for source in users.values())
    assert not users["vendor"]["enabled"]
    assert "initialized=true" in (root / "appcenter.conf").read_text()
    run(env, "enable", remote="flathub-beta", url=users["flathub-beta"]["url"], enabled=False)
    sources = run(env, "initialize")
    assert not next(s for s in sources if s["scope"] == "user" and s["name"] == "flathub-beta")["enabled"]
    run(env, "remove", remote="vendor", url=users["vendor"]["url"])
    sources = run(env, "initialize")
    assert not any(s["scope"] == "user" and s["name"] == "vendor" for s in sources), sources
    assert (root / "system/repo/config").read_bytes() == system_before
    # A third-party source still requires explicit approval, even named flathub.
    repo_file = root / "spoof.flatpakrepo"
    repo_file.write_text("[Flatpak Repo]\nTitle=Flathub\nUrl=https://example.org/repo/\nGPGKey=" + base64.b64encode(KEY).decode() + "\n")
    events = worker(env, dict(action="source", source=str(repo_file), prepareOnly=True))
    assert any(e["type"] == "review" for e in events)
    assert events[-1]["cancelled"]
    assert "spoof" not in (root / "user/repo/config").read_text()
    assert not (root / "user/app").exists()
    print("PASS: system stable/beta/vendor mirroring, signing verification, disabled state, removal persists, system unchanged, untrusted confirmation, no app installations")

if "--online" in sys.argv:
    with tempfile.TemporaryDirectory(prefix="appcenter-first-run-") as directory:
        root = Path(directory)
        env = isolated(root, create=False)
        sources = run(env, "initialize")
        assert len(sources) == 1 and sources[0]["name"] == "flathub" and sources[0]["verified"]
        run(env, "remove", remote="flathub", url=sources[0]["url"])
        assert run(env, "initialize") == []  # Deliberate removal is not another first run.
        assert not (root / "user/app").exists()
        print("PASS: empty first-run Flathub setup, no trust prompt, deliberate removal respected, no apps installed")
