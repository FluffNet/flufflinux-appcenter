#!/usr/bin/env python3
"""Read-only real catalog check. Uses temporary exclusion files, never changes apps."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

binary = Path(__file__).resolve().parents[2] / "target/release/flufflinux-appcenter"
def normalize(app_id):
    return app_id.removesuffix(".desktop")
def catalog(path):
    env = dict(os.environ, FLUFF_APP_CENTER_EXCLUSIONS=str(path))
    return json.loads(subprocess.check_output([str(binary), "--catalog"], env=env, timeout=30))

with tempfile.TemporaryDirectory(prefix="appcenter-catalog-exclusions-") as directory:
    config = Path(directory) / "exclusions.conf"
    config.write_text("")
    before = catalog(config)
    assert before, "This opt-in test requires a populated catalog"
    installed = {normalize(line) for line in subprocess.check_output(
        ["flatpak", "list", "--app", "--columns=application"], text=True).splitlines()}
    installed_apps = [app for app in before if normalize(app["id"]) in installed]
    assert installed_apps, "Test requires at least one installed catalog app"
    absent_app = next(app for app in before if normalize(app["id"]) not in installed)
    config.write_text('# Test exact IDs, comments and installed exception\n'
                      + '\n'.join(app["id"] for app in installed_apps + [absent_app]) + '\n')
    after = catalog(config)
    ids = {normalize(app["id"]) for app in after}
    assert all(normalize(app["id"]) in ids for app in installed_apps), "An installed excluded app became inaccessible"
    assert normalize(absent_app["id"]) not in ids, "An uninstalled excluded app remained in the catalog"
    assert len(after) == len(before) - 1
    defaults = catalog(Path(directory) / "missing.conf")
    for app in defaults:
        if normalize(app["id"]) in {"org.videolan.VLC", "org.libreoffice.LibreOffice"}:
            assert normalize(app["id"]) in installed
    assert any(isinstance(app["downloadBytes"], int) and app["downloadBytes"] > 0 for app in before)
    assert any(app["releaseTimestamp"] or app["releaseDate"] for app in before)
    print("PASS: exact catalog exclusions, installed exception, bundled defaults, cached sizes/release dates")
