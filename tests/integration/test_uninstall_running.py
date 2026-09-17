#!/usr/bin/env python3
"""Opt-in VM test: No preserves running apps; Yes kills every target sandbox.

APPCENTER_MUTATING_TESTS=1 python3 tests/integration/test_uninstall_running.py
Run as the desktop user, with that user's real XDG_RUNTIME_DIR. Refuses to
touch a pre-existing Calculator or its data; never kills unrelated apps.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import time
from unittest.mock import patch

import test_transactions as transactions


def instances():
    output = subprocess.check_output(
        ["flatpak", "ps", "--columns=instance,application"], text=True)
    return {parts[0]: parts[1] for line in output.splitlines()
            if len(parts := line.split()) == 2}


def wait_for(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    raise AssertionError("Timed out waiting for sandbox state")


def main():
    assert os.getenv("APPCENTER_MUTATING_TESTS") == "1", "Opt in on the testing VM only"
    assert os.geteuid() != 0, "Run as the desktop user, not root"
    assert os.getenv("XDG_RUNTIME_DIR") == f"/run/user/{os.geteuid()}", "Use the real desktop runtime"
    app = transactions.APP
    before = set(transactions.installed())
    assert app not in before, "Refusing to remove a pre-existing Calculator"
    data = Path.home() / ".var/app" / app
    assert not data.exists() and not data.is_symlink(), "Refusing to remove pre-existing app data"
    running_before = instances()
    transactions.BINARY = transactions.ROOT / "target/release/flufflinux-appcenter"
    remove = {"action": "uninstall", "id": app, "name": "Calculator", "installation": "user",
              "installedArch": transactions.ARCH, "installedBranch": "stable"}
    children = []
    try:
        transactions.run({"action": "install", "id": app, "name": "Calculator"})
        # Two independent app sandboxes that ignore graceful termination.
        # A SIGTERM-only implementation would leave them alive and fail.
        for _ in range(2):
            children.append(subprocess.Popen([
                "flatpak", "run", "--user", "--command=sh", app, "-c",
                "trap '' TERM INT; while :; do sleep 60; done"]))
        wait_for(lambda: len([value for value in instances().values() if value == app]) == 2)
        target_instances = {key for key, value in instances().items() if value == app}
        marker = data / "app-center-test-marker.txt"
        marker.write_text("Removal must delete this test data, but only after Yes.\n")
        declined = transactions.run(remove, approve=False, expect=False)
        assert declined[-1]["cancelled"]
        assert not any(e.get("status", "").startswith("Closing ") for e in declined)
        assert target_instances.issubset(instances()), "No stopped a running app"
        assert app in transactions.installed() and marker.exists()
        # If force-stop is unavailable, abort without touching deployment/data.
        with tempfile.TemporaryDirectory(prefix="appcenter-kill-failure-") as temp:
            stub = Path(temp) / "flatpak"
            stub.write_text("#!/bin/sh\nexit 1\n")
            stub.chmod(0o755)
            with patch.dict(os.environ, {"PATH": temp + os.pathsep + os.environ["PATH"]}):
                failed = transactions.run(remove, expect=False)
            assert not failed[-1]["cancelled"]
            assert "Nothing has been removed" in failed[-1]["error"]
            assert target_instances.issubset(instances())
            assert app in transactions.installed() and marker.exists()
        events = transactions.run(remove)
        review = next(e for e in events if e["type"] == "review")
        assert review["title"] == "Uninstall Calculator?"
        assert review["message"] == "If you proceed, Calculator and its app data will be removed."
        assert not review.get("message"), "Removal prompt still contains technical details"
        assert any(e.get("status") == "Closing Calculator…" for e in events)
        wait_for(lambda: app not in instances().values())
        for child in children:
            child.wait(timeout=5)
        assert app not in transactions.installed() and not data.exists()
        assert set(transactions.installed()) == before
        assert running_before.items() <= instances().items(), "An unrelated running app was stopped"
        print("PASS: No preserves both running instances and data; failed force-stop aborts safely; Yes force-stops both SIGTERM-resistant sandboxes before uninstall/data deletion; unrelated apps stay running", flush=True)
    finally:
        # Only this test's newly installed app is in scope for cleanup.
        if app in instances().values():
            subprocess.run(["flatpak", "kill", app], check=False)
        for child in children:
            child.wait(timeout=10)
        if app in transactions.installed():
            transactions.run(remove)


if __name__ == "__main__":
    main()
