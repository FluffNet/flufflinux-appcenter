"""Real GUI/worker update-removal overlap. Only temporary apps, data and sources."""
import json
import os
import selectors
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from test_full_update_plan import export
from test_updates import command, commit, environment

binary = str(Path(sys.argv[1]).resolve())
project = Path(__file__).resolve().parents[2]


def sampled_rss(pid):
    """Parent and current descendants; sampled RSS, not an exact memory peak."""
    pending = [str(pid)]
    total = parent = 0
    while pending:
        current = pending.pop()
        base = Path("/proc") / current
        try:
            fields = dict(line.split(":", 1) for line in (base / "status").read_text().splitlines() if ":" in line)
            rss = int(fields.get("VmRSS", "0 kB").split()[0])
            total += rss
            if current == str(pid):
                parent = rss
            pending.extend((base / "task" / current / "children").read_text().split())
        except (OSError, ValueError, ProcessLookupError):
            continue
    return parent, total


with tempfile.TemporaryDirectory(prefix="appcenter-mixed-jobs-") as directory:
    root = Path(directory)
    env = environment(root)
    for name in ("config", "runtime", "home"):
        (root / name).mkdir(mode=0o700)
    (root / "settings").mkdir()
    (root / "settings/flufflinux-appcenter.conf").write_text("[Sources]\ninitialized=true\n")
    env.update(HOME=str(root / "home"), XDG_RUNTIME_DIR=str(root / "runtime"),
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               QT_QUICK_CONTROLS_STYLE="org.kde.desktop", QT_FORCE_STDERR_LOGGING="1",
               FLUFF_APP_CENTER_QML=str(project / "tests/integration/MixedJobsStress.qml"))
    arch = command(env, "flatpak", "--default-arch")
    runtime_id = "org.example.MixedRuntime"
    runtime = f"{runtime_id}/{arch}/stable"
    removal_runtime_id = "org.example.MixedRemovalRuntime"
    removal_runtime = f"{removal_runtime_id}/{arch}/stable"
    updates = [f"org.example.MixedUpdate{i:02}" for i in range(12)]
    removals = [f"org.example.MixedRemove{i:02}" for i in range(12)]
    export(env, root, runtime_id, runtime, 1, True)
    export(env, root, removal_runtime_id, removal_runtime, 1, True)
    for app in updates + removals:
        export(env, root, app, runtime if app in updates else removal_runtime, 1)
    command(env, "flatpak", "build-update-repo", str(root / "repo"))
    command(env, "flatpak", "remote-add", "--user", "--no-gpg-verify", "fixture", str(root / "repo"))
    command(env, "flatpak", "install", "--user", "--noninteractive", "--no-related", "fixture", *updates, *removals)
    old = {app: commit(env, app) for app in updates}
    for app in updates + removals:
        marker = root / "home/.var/app" / app / "config/proof"
        marker.parent.mkdir(parents=True)
        marker.write_text("Preserve unless removal was explicitly approved: " + app)
    export(env, root, runtime_id, runtime, 2, True)
    for app in updates:
        export(env, root, app, runtime, 2)
    command(env, "flatpak", "build-update-repo", str(root / "repo"))
    target = {app: command(env, "ostree", "--repo=" + str(root / "repo"), "rev-parse", f"app/{app}/{arch}/stable")
              for app in updates}
    peak_parent = peak_total = 0
    with (root / "gui.log").open("w+") as log:
        process = subprocess.Popen(["dbus-run-session", "--", binary], env=env, stdout=log, stderr=subprocess.STDOUT)
        start = time.monotonic()
        try:
            while process.poll() is None and time.monotonic() - start < 200:
                # dbus-run-session owns the actual GUI child.
                children = Path(f"/proc/{process.pid}/task/{process.pid}/children")
                for child in children.read_text().split() if children.exists() else []:
                    try:
                        if (Path("/proc") / child / "exe").resolve() != Path(binary):
                            continue
                    except OSError:
                        continue
                    parent, total = sampled_rss(int(child))
                    peak_parent = max(peak_parent, parent)
                    peak_total = max(peak_total, total)
                time.sleep(0.1)
            assert process.poll() is not None, "Mixed jobs exceeded the deadline"
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=10)
    output = (root / "gui.log").read_text()
    print("\n".join(line for line in output.splitlines() if "MIXED_JOBS" in line))
    if process.returncode:
        print(output[-8000:])
    assert process.returncode == 0 and "MIXED_JOBS_PASS" in output
    installed = set(command(env, "flatpak", "list", "--user", "--app", "--columns=application").splitlines())
    assert set(updates) <= installed
    for app in updates:
        assert commit(env, app) == (old[app] if app.endswith("02") else target[app]), app
        assert (root / "home/.var/app" / app / "config/proof").read_text().endswith(app), app
    for index, app in enumerate(removals):
        declined = index % 4 == 0
        assert (app in installed) == declined, app
        marker = root / "home/.var/app" / app / "config/proof"
        assert marker.exists() == declined, app
        if declined:
            assert marker.read_text().endswith(app)
    assert command(env, "flatpak", "info", "--user", "--show-ref", "runtime/" + runtime)
    assert command(env, "flatpak", "remotes", "--user", "--columns=name") == "fixture"
    assert not command(env, "flatpak", "list", "--system", "--columns=ref")
    # Force the app-data cleanup guard, entirely inside this temporary HOME.
    # A legitimate package removal must never follow a substituted data link.
    guarded = removals[0]
    original_data = root / "home/.var/app"
    original_data.rename(root / "declined-data-preserved")
    protected = root / "protected-data"
    protected.mkdir()
    (protected / "sentinel").write_text("Never follow this app-data symlink")
    original_data.symlink_to(protected, target_is_directory=True)
    request = dict(action="uninstall", id=guarded, installation="user",
                   installedBranch="stable", installedArch=arch, removalConfirmed=True)
    stopped = subprocess.Popen([binary, "--transaction-worker", json.dumps(request)],
                               env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    result = None
    try:
        with selectors.DefaultSelector() as watcher:
            watcher.register(stopped.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                if not watcher.select(1):
                    continue
                line = stopped.stdout.readline()
                assert line, stopped.stderr.read().decode()
                event = json.loads(line)
                assert event["type"] != "review", "Removal was already explicitly approved"
                if event["type"] == "result":
                    result = event
                    stopped.stdin.close()
                    stopped.wait(timeout=10)
                    break
        assert result is not None, "Guarded removal timed out"
    finally:
        if stopped.poll() is None:
            stopped.kill()
            stopped.wait(timeout=10)
    assert not result["success"] and "symlink" in result["error"], result
    assert original_data.is_symlink() and (protected / "sentinel").read_text().startswith("Never follow")
    assert (root / "declined-data-preserved" / guarded / "config/proof").read_text().endswith(guarded)
    print(json.dumps(dict(sampledGuiPeakKiB=peak_parent, sampledProcessTreePeakKiB=peak_total)))
    print("PASS: 11 app updates + shared runtime, one queued cancellation, 9 approved removals, 3 declined removals, preserved app data, correct final commits, no unrelated source/system changes")
    print("PASS: unsafe symlinked app data produces an explicit failure and preserves the protected target")
