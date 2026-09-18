#!/usr/bin/env python3
"""Offline app/runtime fixtures in fresh /tmp installations, never real apps.

Usage: test_source_removal.py target/test-source-worker target/test-source-removal
Add --system when running as root to cover default/named/merged system sources.
Only the test driver honors temporary system paths; the production helper does not.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

WORKER, DRIVER = (str(Path(arg).resolve()) for arg in sys.argv[1:3])
SYSTEM = "--system" in sys.argv
assert not SYSTEM or os.geteuid() == 0, "Temporary system checks require root"


def command(env, *args):
    result = subprocess.run(args, env=env, capture_output=True, text=True)
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    return result.stdout


def snapshot(installation):
    result = {}
    for kind in ("app", "runtime", "exports"):
        for path in sorted((installation / kind).rglob("*")):
            name = str(path.relative_to(installation))
            if path.is_symlink():
                result[name] = ("link", os.readlink(path))
            elif path.is_file():
                result[name] = (path.stat().st_mode, hashlib.sha256(path.read_bytes()).hexdigest())
    assert any(name.startswith("app/") for name in result)
    assert any(name.startswith("runtime/") for name in result)
    return result


for removal in (["user", "default", "extra", "merged"] if SYSTEM else ["worker", "user"]):
    with tempfile.TemporaryDirectory(prefix="appcenter-remove-used-", dir="/tmp") as directory:
        root = Path(directory)
        env = dict(os.environ, FLATPAK_USER_DIR=str(root / "user"),
                   FLATPAK_SYSTEM_DIR=str(root / "system"), FLATPAK_CONFIG_DIR=str(root / "config"),
                   XDG_DATA_HOME=str(root / "data"), XDG_CACHE_HOME=str(root / "cache"),
                   APPCENTER_TEST_CONFIG=str(root / "appcenter.conf"), APPCENTER_REMOVAL_FIXTURE=str(root))
        (root / "config/installations.d").mkdir(parents=True)
        (root / "config/installations.d/extra.conf").write_text(
            f'[Installation "extra"]\nPath={root / "extra"}\nDisplayName=Temporary test installation\n')
        arch = command(env, "/usr/bin/flatpak", "--default-arch").strip()
        runtime = f"org.flufflinux.SourceRemovalRuntime/{arch}/stable"
        app = f"org.flufflinux.SourceRemovalTest/{arch}/stable"
        for kind, metadata in (("runtime", f"[Runtime]\nname=org.flufflinux.SourceRemovalRuntime\nruntime={runtime}\nsdk={runtime}\n"),
                               ("app", f"[Application]\nname=org.flufflinux.SourceRemovalTest\nruntime={runtime}\nsdk={runtime}\ncommand=fixture\n")):
            build = root / ("build-" + kind)
            payload = build / ("usr" if kind == "runtime" else "files")
            (payload / "bin").mkdir(parents=True)
            (build / "files").mkdir(exist_ok=True)
            (build / "metadata").write_text(metadata)
            (payload / "bin/fixture").write_text("#!/bin/sh\nexit 0\n")
            (payload / "bin/fixture").chmod(0o755)
            (build / "export").mkdir()
            command(env, "/usr/bin/flatpak", "build-export", *(["--runtime"] if kind == "runtime" else []),
                    str(root / "repo"), str(build), "stable")
        scopes = {"user": ("--user", root / "user")}
        if SYSTEM:
            scopes.update(default=("--installation=default", root / "system"), extra=("--installation=extra", root / "extra"))
        before = {}
        for scope, (option, installation) in scopes.items():
            command(env, "/usr/bin/flatpak", "remote-add", option, "--no-gpg-verify", "fixture", str(root / "repo"))
            command(env, "/usr/bin/flatpak", "install", option, "--noninteractive", "--no-related", "fixture", "runtime/" + runtime, "app/" + app)
            before[scope] = (snapshot(installation), command(env, "/usr/bin/flatpak", "list", option, "--columns=ref,origin,active"))
        if removal == "worker":
            def worker(operation, **fields):
                # EOF on the review/control pipe means cancellation to a real
                # worker. Keep it open until the terminal result arrives.
                events = []
                with subprocess.Popen([WORKER, json.dumps(dict(action="repositories", operation=operation, **fields))],
                                      env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True) as child:
                    while True:
                        line = child.stdout.readline()
                        assert line, child.stderr.read()
                        events.append(json.loads(line))
                        if events[-1]["type"] == "result":
                            break
                    child.stdin.close()
                    child.wait(timeout=10)
                assert events[-1]["success"], events
                return next(event["sources"] for event in events if event["type"] == "sources")
            rows = worker("list")
            member = next(member for row in rows for member in row["members"] if member["scope"] == "user")
            worker("remove", members=[member])
        else:
            command(env, DRIVER, removal)
        removed = set(scopes) if removal == "merged" else {"user" if removal == "worker" else removal}
        for scope, (option, installation) in scopes.items():
            remotes = command(env, "/usr/bin/flatpak", "remotes", option, "--columns=name").splitlines()
            assert ("fixture" not in remotes) == (scope in removed), (scope, remotes)
            assert snapshot(installation) == before[scope][0], "Deployed app/runtime files changed"
            assert command(env, "/usr/bin/flatpak", "list", option, "--columns=ref,origin,active") == before[scope][1]
            if scope in removed:
                command(env, "/usr/bin/flatpak", "remote-add", option, "--no-gpg-verify", "fixture", str(root / "repo"))
                assert snapshot(installation) == before[scope][0]
                assert command(env, "/usr/bin/flatpak", "info", option, "--show-origin", "org.flufflinux.SourceRemovalTest").strip() == "fixture"
        print(f"PASS: {removal} in-use removal preserves apps, runtime, exports, origins and unrelated scopes; source can be restored", flush=True)
