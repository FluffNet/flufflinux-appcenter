#!/usr/bin/env python3
"""Explicitly opt-in, destructive integration test. Run on the disposable VM.

APPCENTER_MUTATING_TESTS=1 python3 tests/integration/test_transactions.py
Requires a regular user and network access. No system authorization is needed.
Refuses to touch the test app if it is already installed. Never prunes unrelated
apps/runtimes. New runtimes are left installed for repeated test runs.
"""
import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "target/debug/flufflinux-appcenter"
APP = "org.gnome.Calculator"
ARCH = subprocess.check_output(["flatpak", "--default-arch"], text=True).strip()
REF = f"app/{APP}/{ARCH}/stable"


def installed():
    return subprocess.check_output(["flatpak", "list", "--app", "--columns=application"], text=True).splitlines()


def run(request, approve=True, expect=True):
    events = []
    child = subprocess.Popen([str(BINARY), "--transaction-worker", json.dumps(request)],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=None,
                             bufsize=0)
    selector = selectors.DefaultSelector()
    selector.register(child.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + 900
    result = None
    try:
        while time.monotonic() < deadline:
            if not selector.select(1):
                if child.poll() is not None:
                    break
                continue
            line = child.stdout.readline()
            if not line:
                break
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            events.append(event)
            if event["type"] == "review":
                print("REVIEW", event.get("title"), len(event.get("operations", [])), flush=True)
                child.stdin.write((json.dumps({"token": event["token"], "accept": approve}) + "\n").encode())
                child.stdin.flush()
            if event["type"] == "result":
                result = event
                child.stdin.close()
                break
        assert result is not None, "Worker did not complete within the test timeout"
        child.wait(15)
        assert result["success"] == expect, result
        print("RESULT", result, flush=True)
        return events
    finally:
        if child.poll() is None:
            if not child.stdin.closed:
                child.stdin.write(b'{"cancel":true}\n')
                child.stdin.close()
            try:
                child.wait(20)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        selector.close()


def main():
    assert os.getenv("APPCENTER_MUTATING_TESTS") == "1", "Set APPCENTER_MUTATING_TESTS=1 on the testing VM only"
    assert os.geteuid() != 0, "Do not run as root"
    before = set(installed())
    assert APP not in before, f"Refusing to modify pre-existing {APP}"
    data_dir = Path.home() / ".var/app" / APP
    assert not data_dir.exists() and not data_dir.is_symlink(), "Refusing to delete pre-existing app data"
    system_before = subprocess.check_output(["flatpak", "list", "--system", "--columns=ref"], text=True)
    system_remotes = subprocess.check_output(["flatpak", "remotes", "--system", "--columns=name,url"], text=True)
    # Even a stale request naming "system" must never create a system install.
    install = {"action": "install", "id": APP, "name": "Calculator", "installation": "system"}
    remove = {"action": "uninstall", "id": APP, "installation": "user", "installedBranch": "stable", "installedArch": ARCH}
    invalid = run({"action": "uninstall", "id": "../../Documents"}, expect=False)
    assert not any(e["type"] == "review" for e in invalid)
    prepared = run(dict(install, estimateOnly=True))
    assert APP not in installed()
    assert not any(e["type"] in ("review", "operation") for e in prepared)
    estimate = next(e for e in prepared if e["type"] == "plan")
    existing_refs = set(subprocess.check_output(["flatpak", "list", "--columns=ref"], text=True).splitlines())
    assert estimate["totalBytes"] == sum(op["downloadBytes"] for op in estimate["operations"])
    assert estimate["appBytes"] == sum(op["downloadBytes"] for op in estimate["operations"] if not op["dependency"])
    assert all(op["ref"] not in existing_refs for op in estimate["operations"] if op["dependency"]), "Existing dependencies inflated the estimate"
    events = run(install)
    plan = next(e for e in events if e["type"] == "plan")
    assert not any(e["type"] == "review" and e["kind"] == "transaction" for e in events)
    assert any(op["ref"] == REF for op in plan["operations"])
    assert all("downloadSize" in op and "dependency" in op for op in plan["operations"])
    assert any(e["type"] == "operation" and e["progress"] == 1 for e in events)
    assert APP in installed()
    subprocess.run(["flatpak", "info", "--user", APP], check=True)
    data_dir.mkdir(parents=True)
    marker = data_dir / "app-center-uninstall-test.txt"
    marker.write_text("This must not survive the test uninstall.\n")
    run(remove, approve=False, expect=False)
    assert APP in installed() and marker.exists()
    run(remove)
    assert APP not in installed() and not data_dir.exists()
    with tempfile.TemporaryDirectory(prefix="appcenter-flatpakref-") as temp:
        reference = Path(temp) / "calculator.flatpakref"
        reference.write_text(f"[Flatpak Ref]\nName={APP}\nBranch=stable\nUrl=https://dl.flathub.org/repo/\nIsRuntime=false\n")
        run({"action": "source", "source": reference.as_uri(), "prepareOnly": True})
        assert APP not in installed(), "Opening a reference silently installed it"
        run({"action": "source", "source": reference.as_uri(), "id": "org.example.WrongApp"}, expect=False)
        run({"action": "source", "source": reference.as_uri()})
        assert APP in installed() and not marker.exists()
        bundle = Path(temp) / "calculator.flatpak"
        user_repo = Path(os.getenv("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "flatpak/repo"
        subprocess.run(["flatpak", "build-bundle", "--repo-url=https://dl.flathub.org/repo/",
                        "--gpg-keys=" + str(user_repo / "flathub.trustedkeys.gpg"),
                        str(user_repo), str(bundle), APP, "stable"], check=True)
        external = Path(temp) / "unrelated-documents"
        external.mkdir()
        sentinel = external / "keep.txt"
        sentinel.write_text("Uninstall must not follow a sandbox directory symlink.\n")
        data_dir.symlink_to(external, target_is_directory=True)
        run(remove)
        assert sentinel.exists() and not data_dir.is_symlink(), "Uninstall followed a symlink into unrelated data"
        run({"action": "source", "source": bundle.as_uri(), "prepareOnly": True})
        assert APP not in installed(), "Opening a bundle silently installed it"
        run({"action": "source", "source": bundle.as_uri()})
        assert APP in installed()
        run(remove)
        repo_name = "appcenter-integration-source"
        assert repo_name not in subprocess.check_output(["flatpak", "remotes", "--user", "--columns=name"], text=True).splitlines()
        repo_file = Path(temp) / (repo_name + ".flatpakrepo")
        urllib.request.urlretrieve("https://dl.flathub.org/repo/flathub.flatpakrepo", repo_file)
        run({"action": "source", "source": repo_file.as_uri()}, approve=False, expect=False)
        run({"action": "source", "source": repo_file.as_uri()})
        duplicate = run({"action": "source", "source": repo_file.as_uri()}, expect=False)
        assert "already configured" in duplicate[-1]["error"]
        subprocess.run(["flatpak", "remote-delete", "--user", repo_name], check=True)
    # A browser link opens an app page, never silently starts deployment.
    run({"action": "source", "source": f"flatpak+https://dl.flathub.org/repo/appstream/{APP}.flatpakref", "prepareOnly": True})
    run({"action": "source", "source": "http://example.org/unsafe.flatpakref"}, expect=False)
    run({"action": "install", "id": "org.example.DoesNotExistInFlathub"}, expect=False)
    assert set(installed()) == before, "Installed apps changed outside the test target"
    assert subprocess.check_output(["flatpak", "list", "--system", "--columns=ref"], text=True) == system_before, "System installations changed"
    assert subprocess.check_output(["flatpak", "remotes", "--system", "--columns=name,url"], text=True) == system_remotes, "System sources changed"
    print("PASS: user-only dependency plan, progress, cancellation, install, data-removing uninstall, fresh reinstall, local reference/bundle/repository, browser link and error paths; system unchanged", flush=True)


if __name__ == "__main__":
    main()
