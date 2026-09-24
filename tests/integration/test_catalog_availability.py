#!/usr/bin/env python3
"""Real worker, local temporary repositories, no network or installed app changes."""
import gzip
import json
import os
import selectors
from pathlib import Path
import subprocess
import sys
import tempfile
import time

worker = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="appcenter-catalog-load-") as directory:
    root = Path(directory)
    env = dict(os.environ, FLATPAK_USER_DIR=str(root / "user"),
               FLATPAK_SYSTEM_DIR=str(root / "system"), FLATPAK_CONFIG_DIR=str(root / "config"),
               XDG_DATA_HOME=str(root / "data"), XDG_CACHE_HOME=str(root / "cache"),
               APPCENTER_TEST_CONFIG=str(root / "appcenter.conf"))
    (root / "config").mkdir()
    (root / "appcenter.conf").write_text("[Sources]\ninitialized=true\n")

    def command(*args):
        result = subprocess.run(args, env=env, capture_output=True, text=True)
        assert result.returncode == 0, (args, result.stderr)
        return result.stdout

    def check(available, failed, operation="initialize"):
        child = subprocess.Popen([worker, json.dumps({"action": "repositories", "operation": operation})],
                                 env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        events = []
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(child.stdout, selectors.EVENT_READ)
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    if not selector.select(1):
                        continue
                    line = child.stdout.readline()
                    assert line, child.stderr.read().decode()
                    events.append(json.loads(line))
                    if events[-1]["type"] == "result":
                        child.stdin.close()
                        child.wait(5)
                        break
                else:
                    raise AssertionError("Catalog worker timed out")
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
        reports = [event for event in events if event["type"] == "catalog-load"]
        assert reports == [{"type": "catalog-load", "available": available, "failed": failed}], events
        assert not any(event["type"] in ("review", "updates", "plan") for event in events), events

    for scope in ("user", "system"):
        (root / scope).mkdir()
        command("ostree", "--repo=" + str(root / scope / "repo"), "init", "--mode=bare-user-only")
    check(0, 0)  # Deliberately empty source list is not a connection failure.
    for name in ("one", "two"):
        with (root / "user/repo/config").open("a") as config:
            config.write(f'\n[remote "{name}"]\nurl={(root / (name + "-missing")).as_uri()}\ngpg-verify=false\n')
    check(0, 2)
    arch = command("flatpak", "--default-arch").strip()
    cache = root / "user/appstream/one" / arch / "active"
    cache.mkdir(parents=True)
    (cache / "appstream.xml.gz").write_bytes(gzip.compress(b"<components/>"))
    check(1, 1)  # A valid empty cache is still a successful source load.
    check(1, 1, "refresh")  # Failed refresh preserves usable cached catalogs.
    command("flatpak", "remote-modify", "--user", "--disable", "two")
    check(1, 0)  # Disabled sources aren't failures.
    command("flatpak", "remote-modify", "--user", "--disable", "one")
    check(0, 0)
    command("flatpak", "remote-delete", "--user", "one")
    command("flatpak", "remote-delete", "--user", "two")
    # A fresh local source succeeds without a prior catalog (no Internet test).
    repository = root / "working-repo"
    command("ostree", "--repo=" + str(repository), "init", "--mode=archive-z2")
    metadata = root / "metadata"
    metadata.mkdir()
    (metadata / "appstream.xml.gz").write_bytes(gzip.compress(b"<components/>"))
    command("ostree", "--repo=" + str(repository), "commit", "--branch=appstream/" + arch,
            "--subject=Test catalog", "--tree=dir=" + str(metadata))
    command("ostree", "--repo=" + str(repository), "summary", "--update")
    command("flatpak", "remote-add", "--user", "--no-gpg-verify", "working", repository.as_uri())
    check(1, 0, "refresh")
    assert not (root / "user/app").exists() and not (root / "system/app").exists()
    print("PASS: real worker all-failed, partial/cache/empty success, disabled and removed sources, fresh recovery; no app changes")
