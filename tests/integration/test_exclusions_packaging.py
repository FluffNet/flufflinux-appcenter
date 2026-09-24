#!/usr/bin/env python3
"""Exercise make install entirely inside temporary staging directories."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
defaults = (repo / "data/exclusions.conf").read_bytes()
with tempfile.TemporaryDirectory(prefix="appcenter-exclusions-packaging-") as directory:
    root = Path(directory)
    config = root / "host-etc"
    local = config / "flufflinux-appcenter/exclusions.conf"
    stage = root / "fakeroot"
    staged = stage / str(local).lstrip("/")
    def install(destination, *options):
        with (root / "install.log").open("wb") as log:
            subprocess.run(["make", "install", f"DESTDIR={destination}",
                            f"SYSCONFDIR={config}", *options], cwd=repo,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
    install(stage)
    assert staged.read_bytes() == defaults
    local.parent.mkdir(parents=True)
    local.write_text("# Custom distro choices\norg.example.Custom\nORG.WINEHQ.WINE*\nOrg.KDE.Kate.Desktop\n")
    install(stage)
    assert staged.read_bytes() == local.read_bytes(), "fakeroot must inherit host exclusions"
    install(stage, "EXCLUSIONS_FILE=data/exclusions.conf")
    assert staged.read_bytes() == defaults, "explicit defaults-only builds must be reproducible"
    assert "org.example.Custom" in local.read_text(), "staging must not edit the host config"
    # Exercise the no-DESTDIR preservation guard safely under a temporary prefix.
    install("", f"PREFIX={root / 'installed'}", "EXCLUSIONS_FILE=data/exclusions.conf")
    assert "org.example.Custom" in local.read_text(), "reinstall must preserve admin edits"
    print("PASS: defaults, host exclusions inherited by fakeroot, explicit override, reinstall preservation")
