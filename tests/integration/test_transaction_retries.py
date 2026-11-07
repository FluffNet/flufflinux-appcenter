#!/usr/bin/env python3
"""Fault real HTTP pulls in disposable Flatpak repos; never desktop apps."""
import http.server
import json
import os
from pathlib import Path
import re
import tempfile
import threading

from test_updates import IDS, command, commit, environment, scan, test, worker


class Repository(http.server.SimpleHTTPRequestHandler):
    fault = ""
    object_path = ""
    faults = 0

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == type(self).object_path and type(self).fault:
            type(self).faults += 1
            if type(self).fault == "corrupt":
                data = b"invalid OSTree payload"
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_error(int(type(self).fault), "isolated fixture failure")
            return
        super().do_GET()


def probe(root):
    # Reuse the complete offline fixture, ending with installed v1 apps.
    # No cached v3+ payload exists locally.
    test(root)
    env = environment(root)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0),
        lambda *args, **kwargs: Repository(*args, directory=str(root / "repo"), **kwargs))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    origin = f"http://127.0.0.1:{server.server_port}/"
    command(env, "flatpak", "remote-modify", "--user", "--url=" + origin, "update-fixture")
    app_ref = next(ref for ref in json.loads((root / "manifest.json").read_text())["old"]
                   if "/" + IDS[0] + "/" in ref)
    build = root / f"build-{IDS[0]}-v2"
    payload = build / "files/share/transfer-fixture"

    def publish(revision):
        # A fresh incompressible object ensures the actual network pull runs.
        payload.write_bytes(os.urandom(256 * 1024) + bytes([revision]))
        command(env, "flatpak", "build-export", str(root / "repo"), str(build), "stable")
        command(env, "flatpak", "build-update-repo", str(root / "repo"))
        listing = command(env, "ostree", "--repo=" + str(root / "repo"), "ls", "-C", app_ref, "/files/share/transfer-fixture")
        checksum = re.findall(r"\b[0-9a-f]{64}\b", listing)[0]
        row = next(row for row in scan(env) if row["id"] == IDS[0])
        Repository.object_path = f"/objects/{checksum[:2]}/{checksum[2:]}.filez"
        Repository.faults = 0
        return dict(row, action="update")

    try:
        for revision, code in [(3, "503"), (4, "404")]:
            request = publish(revision)
            Repository.fault = code

            def recover(event, child):
                if event.get("retrying"):
                    Repository.fault = ""

            events = worker(env, request, on_event=recover)
            assert events[-1]["success"] and 1 < events[-1]["attempts"] <= 3, events
            assert Repository.faults > 0 and commit(env, app_ref) == request["commit"], events

        request = publish(5)
        previous = commit(env, app_ref)
        Repository.fault = "503"
        failed = worker(env, request)
        assert not failed[-1]["success"] and failed[-1]["attempts"] == 3, failed
        assert failed[-1]["errorKind"] == "network" and failed[-1]["retryable"], failed
        assert commit(env, app_ref) == previous
        Repository.fault = ""
        assert worker(env, request)[-1]["success"], "Retry required another scan"

        request = publish(6)
        previous = commit(env, app_ref)
        Repository.fault = "503"

        def cancel_retry(event, child):
            if event.get("retrying"):
                child.stdin.write(b'{"cancel":true}\n')
                child.stdin.flush()

        cancelled = worker(env, request, on_event=cancel_retry)
        assert cancelled[-1]["cancelled"] and cancelled[-1]["attempts"] == 1, cancelled
        assert commit(env, app_ref) == previous

        for fault in ["403", "corrupt"]:
            Repository.fault = fault
            refused = worker(env, request)
            assert not refused[-1]["success"] and refused[-1]["attempts"] == 1, refused
            assert not refused[-1]["retryable"] and commit(env, app_ref) == previous, refused
        Repository.fault = ""
        assert worker(env, request)[-1]["success"], "A rejected corrupt payload poisoned retry"
        request = publish(7)
        command(env,"flatpak","uninstall","--user","--noninteractive","--no-related",IDS[0])
        Repository.fault = "503"
        installed = worker(env, {"action":"install","id":IDS[0],"remote":"update-fixture",
            "sourceUrl":origin,"flatpakRef":app_ref}, on_event=recover)
        assert installed[-1]["success"] and 1 < installed[-1]["attempts"] <= 3, installed
        assert commit(env,app_ref) == request["commit"], installed
        duplicate = worker(env, {"action":"install","id":IDS[0],"remote":"update-fixture",
            "sourceUrl":origin,"flatpakRef":app_ref})
        assert duplicate[-1]["success"], "An already installed target was reported as a failed installation: " + str(duplicate)
        print("PASS: real HTTP 503/404 update/install recovery, maximum three attempts, unchanged deployment on failure, retry without scan, cancellation during backoff, permanent HTTP/auth and corrupt-payload stop, clean retry after corruption", flush=True)
    finally:
        Repository.fault = ""
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="appcenter-retry-test-") as directory:
        probe(Path(directory))
