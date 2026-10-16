#!/usr/bin/env python3
"""Real offline solver cleanup/replacement tests. Never use desktop installations."""
import json
import re
from pathlib import Path
import tempfile

from test_updates import command, commit, environment, scan, worker


def export(env, root, app, runtime, revision, is_runtime=False, extra=()):
    build = root / f"build-{app}-{revision}"
    payload = build / ("usr" if is_runtime else "files")
    (payload / "bin").mkdir(parents=True)
    (build / "files").mkdir(exist_ok=True)
    (build / "export").mkdir()
    metadata = f'[{"Runtime" if is_runtime else "Application"}]\nname={app}\nruntime={runtime}\nsdk={runtime}\n'
    if not is_runtime:
        metadata += "command=fixture\n[Context]\nsockets=wayland;\n"
    (build / "metadata").write_text(metadata)
    (payload / "bin/fixture").write_text(f"#!/bin/sh\n# {app} {revision}\nexit 0\n")
    (payload / "bin/fixture").chmod(0o755)
    command(env, "flatpak", "build-export", *(["--runtime"] if is_runtime else []),
            *extra, str(root / "repo"), str(build), "stable")
    return build


def refs(env):
    return {kind + "/" + ref for kind in ["app", "runtime"]
            for ref in command(env, "flatpak", "list", "--user", "--" + kind, "--columns=ref").splitlines()}


def test(root):
    env = environment(root)
    # Also isolate sandbox data to prove that update replacements never erase it.
    env["HOME"] = str(root / "home")
    (root / "config").mkdir()
    arch = command(env, "flatpak", "--default-arch")
    app = "org.flufflinux.FullPlanApp"
    other = "org.flufflinux.FullPlanOther"
    replacement = "org.flufflinux.FullPlanReplacement"
    old = "org.flufflinux.FullPlanOldRuntime"
    new = "org.flufflinux.FullPlanNewRuntime"
    spare = "org.flufflinux.FullPlanPinnedRuntime"
    reference = lambda name, kind="app": f"{kind}/{name}/{arch}/stable"
    old_runtime = f"{old}/{arch}/stable"
    new_runtime = f"{new}/{arch}/stable"
    for name in [old, spare]:
        export(env, root, name, f"{name}/{arch}/stable", 1, True, ("--end-of-life=Fixture retired",))
    for name in [app, other]:
        export(env, root, name, old_runtime, 1)
    command(env, "flatpak", "remote-add", "--user", "--no-gpg-verify", "fixture", str(root / "repo"))
    command(env, "flatpak", "install", "--user", "--noninteractive", "fixture", app, other, spare)
    old_ref = reference(old, "runtime")
    app_ref = reference(app)
    app_v1 = commit(env, app_ref)
    # This pinned EOL runtime must survive solver cleanup.
    command(env, "flatpak", "pin", "--user", reference(spare, "runtime"))
    export(env, root, new, new_runtime, 1, True, ("--end-of-life=Fixture retired",))
    export(env, root, app, new_runtime, 2)
    # Another installed app still needs old_runtime: it must not be removed.
    first = next(r for r in scan(env) if r["id"] == app)
    assert not any(op["action"] == "uninstall" and op["ref"] == old_ref for op in first["plan"]), first
    done = worker(env, dict(first, action="update"))
    assert done[-1]["success"], done
    assert old_ref in refs(env), "Removed a runtime still needed by another app"
    # Move the final consumer too; Flatpak may now clean up the retired runtime.
    export(env, root, other, new_runtime, 2)
    second = next(r for r in scan(env) if r["id"] == other)
    removals = [op for op in second["plan"] if op["action"] == "uninstall"]
    assert any(op["ref"] == old_ref and op["installedCommit"] for op in removals), second
    assert all(op["downloadBytes"] == 0 for op in removals), removals
    before = refs(env)
    assert old_ref in before, "Scanning removed a runtime"
    cancelled = worker(env, dict(second, action="update"), cancel=True)
    assert not cancelled[-1]["success"] and refs(env) == before, cancelled
    tampered = dict(second, action="update", plan=[dict(op, installedCommit="0" * 64)
                    if op["action"] == "uninstall" else op for op in second["plan"]])
    rejected = worker(env, tampered)
    assert not rejected[-1]["success"] and refs(env) == before, rejected
    done = worker(env, dict(second, action="update"))
    assert done[-1]["success"] and old_ref not in refs(env), done
    assert reference(spare, "runtime") in refs(env), "Removed a pinned runtime"
    assert any(e.get("phase") == "uninstall" for e in done), done
    assert worker(env, dict(second, action="update"))[-1]["success"], "Completed plan was not idempotent"
    # Mark an app as replaced by another app ID, from the same configured source.
    export(env, root, replacement, new_runtime, 1)
    export(env, root, app, new_runtime, 3, extra=("--end-of-life-rebase=" + replacement,))
    preserved = root / "home/.var/app" / app / "config/user-data"
    preserved.parent.mkdir(parents=True)
    preserved.write_text("Keep my app data")
    third = next(r for r in scan(env) if r["id"] == app)
    assert third["targetRef"] == reference(replacement), third
    assert any(op["ref"] == app_ref and op["action"] == "uninstall" for op in third["plan"]), third
    assert any(op["ref"] == reference(replacement) and op["action"] == "install" for op in third["plan"]), third
    assert app_ref in refs(env) and reference(replacement) not in refs(env), "Scan deployed a replacement"
    # Publication changes between scan and update still abort before any removal.
    export(env, root, replacement, new_runtime, 2)
    changed = worker(env, dict(third, action="update"))
    assert not changed[-1]["success"] and app_ref in refs(env), changed
    assert reference(replacement) not in refs(env), changed
    third = next(r for r in scan(env) if r["id"] == app)
    # Fail the replacement's actual payload pull AFTER its metadata resolved.
    # The old app must not be removed if the successor cannot be installed.
    listing = command(env, "ostree", "--repo=" + str(root / "repo"), "ls", "-C",
                      reference(replacement), "/files/bin/fixture")
    checksum = re.findall(r"\b[0-9a-f]{64}\b", listing)[0]
    payload = root / "repo/objects" / checksum[:2] / (checksum[2:] + ".filez")
    backup = root / "withheld-payload"
    payload.rename(backup)
    try:
        failed = worker(env, dict(third, action="update"))
        assert not failed[-1]["success"], failed
        assert app_ref in refs(env) and reference(replacement) not in refs(env), failed
        assert preserved.read_text() == "Keep my app data"
    finally:
        backup.rename(payload)
    done = worker(env, dict(third, action="update"))
    assert done[-1]["success"], done
    assert app_ref not in refs(env) and reference(replacement) in refs(env), done
    assert preserved.read_text() == "Keep my app data", "Replacement deleted user data"
    for filename in ["installation-dates.json", "update-dates.json"]:
        saved = list((root / "data").rglob(filename))
        assert len(saved) == 1, saved
        history = json.loads(saved[0].read_text())["installations"]
        assert "user:" + app_ref not in history, history
        assert "user:" + reference(replacement) in history, history
        assert all(key.startswith("user:") for key in history), history
    assert worker(env, dict(third, action="update"))[-1]["success"], "Already-replaced queued app failed"
    assert all(r["id"] != app for r in scan(env)), "Old replaced app still offered"
    assert commit(env, reference(replacement)) == third["commit"]
    assert app_v1 != first["commit"]
    # Both apps are queued from ONE scan. Cleanup only becomes eligible when
    # the final consumer updates, after the first queued transaction has run.
    latest = "org.flufflinux.FullPlanLatestRuntime"
    latest_runtime = f"{latest}/{arch}/stable"
    export(env, root, latest, latest_runtime, 1, True)
    for name in [other, replacement]:
        export(env, root, name, latest_runtime, 4)
    queued = {r["id"]: r for r in scan(env)}
    for name in [other, replacement]:
        assert not any(op["ref"] == reference(new, "runtime") and op["action"] == "uninstall"
                       for op in queued[name]["plan"]), queued[name]
        done = worker(env, dict(queued[name], action="update"))
        assert done[-1]["success"], done
    assert reference(new, "runtime") not in refs(env), "Newly-unused queued runtime was not removed"
    assert reference(spare, "runtime") in refs(env)
    print("PASS: real solver runtime cleanup, in-use/pinned protection, read-only scan, cancellation, removal snapshot verification, correct progress, app replacement, stale target rejection, failed replacement preserves old app, retry, scoped history, idempotent queue, newly-unused queued cleanup, preserved app data", flush=True)


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="appcenter-full-plan-") as directory:
        test(Path(directory))
