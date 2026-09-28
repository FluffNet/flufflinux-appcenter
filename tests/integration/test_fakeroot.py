#!/usr/bin/env python3
"""Test staging and direct install in temporary roots, never on the host system.

Build first with make. Reuse the resulting binaries to test packaging separately
from compilation. No package archive is created or installed by this test.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="appcenter-fakeroot-test-") as temporary:
    root = Path(temporary)
    source = root / "source with spaces"
    source.mkdir()
    for name in ("Cargo.toml", "Cargo.lock", "VERSION", "LICENSE", "Makefile", "build.rs"):
        shutil.copy2(repo / name, source / name)
    for name in ("src", "qml", "assets", "data", "scripts", "packaging"):
        shutil.copytree(repo / name, source / name)
    binaries = source / "target/release"
    binaries.mkdir(parents=True)
    for name in ("flufflinux-appcenter", "flufflinux-appcenter-source-helper"):
        target = binaries / name
        shutil.copy2(repo / "target/release" / name, target)
        target.touch()
    curated = root / "curated exclusions.conf"
    curated.write_text("# Curated ID list\norg.example.Custom\nORG.WINEHQ.WINE*\n")
    env = dict(os.environ, SOURCE_DATE_EPOCH="1790553600")
    log = root / "make.log"
    def make(*arguments, success=True):
        with log.open("w") as stream:
            result = subprocess.run(["make", *arguments], cwd=source, env=env,
                                    stdout=stream, stderr=subprocess.STDOUT)
        assert (result.returncode == 0) == success, log.read_text()
    def stage(*arguments, success=True):
        make("-o", "build", "fakeroot", f"EXCLUSIONS_FILE={curated}", *arguments, success=success)
    make("-n", "fakeroot")
    assert not (source / "fakeroot").exists(), "dry-run must not prepare staging"
    stage()
    staged = source / "fakeroot"
    assert staged.stat().st_mode & 0o777 == 0o755
    assert (staged / "etc/flufflinux-appcenter/exclusions.conf").read_bytes() == curated.read_bytes()
    metadata = (staged / ".PKGINFO").read_text()
    assert "builddate = 1790553600" in metadata
    assert (staged / ".INSTALL").read_bytes() == (source / "packaging/INSTALL").read_bytes()
    subprocess.run(["python3", repo / "tests/integration/test_pacman_package.py", staged], check=True)
    assert not (staged / "usr/share/applications/mimeinfo.cache").exists(), "staging must not run cache hooks"
    assert not list(source.rglob("*.pkg.tar.*")), "package creation is manual"
    marker = staged / "manual-test-note"
    marker.write_text("preserve me in the previous tree")
    stage()
    assert not marker.exists(), "each fakeroot must be a fresh tree"
    backups = list((source / "build").glob("fakeroot-backup.*/fakeroot/manual-test-note"))
    assert len(backups) == 1 and backups[0].read_text() == "preserve me in the previous tree"
    stage("EXCLUSIONS_FILE=/does/not/exist", success=False)
    assert (staged / ".PKGINFO").read_text() == metadata, "failure must preserve the last completed staging"
    stage("SOURCE_DATE_EPOCH=invalid", success=False)
    assert (staged / ".PKGINFO").read_text() == metadata
    stage("EXCLUSIONS_FILE=data/exclusions.conf")
    assert (staged / "etc/flufflinux-appcenter/exclusions.conf").read_bytes() == (source / "data/exclusions.conf").read_bytes()

    # Use the real make install/uninstall and shared hooks in an alternate root.
    prefix, config = root / "installed", root / "etc"
    defaults = config / "xdg/mimeapps.list"
    defaults.parent.mkdir(parents=True)
    original = "[Default Applications]\ntext/plain=editor.desktop;\napplication/vnd.flatpak=old.desktop;\n"
    defaults.write_text(original)
    options = [f"PREFIX={prefix}", f"SYSCONFDIR={config}", f"EXCLUSIONS_FILE={curated}"]
    make("install", *options)
    assert (prefix / "bin/flufflinux-appcenter").is_file()
    assert "flufflinux-appcenter.desktop;old.desktop;" in defaults.read_text()
    assert "text/plain=editor.desktop;" in defaults.read_text()
    assert (prefix / "share/applications/mimeinfo.cache").is_file()
    assert (prefix / "share/icons/hicolor/icon-theme.cache").is_file()
    registered = defaults.read_bytes()
    make("install", *options)
    assert defaults.read_bytes() == registered, "reinstall hooks must be idempotent"
    make("uninstall", *options)
    assert not (prefix / "bin/flufflinux-appcenter").exists()
    assert not (prefix / "bin/plasma-discover").is_symlink()
    assert defaults.read_text() == original
    assert (config / "flufflinux-appcenter/exclusions.conf").read_bytes() == curated.read_bytes()
    # Do not follow a manually replaced staging symlink into another directory.
    saved = source / "saved-fakeroot"
    staged.rename(saved)
    staged.symlink_to(saved, target_is_directory=True)
    stage(success=False)
    assert staged.is_symlink() and (saved / ".PKGINFO").is_file()
print("PASS: fresh fakeroot, metadata/hooks, custom exclusions, safe reruns/failures, no archive, direct install/uninstall hooks and preserved config")
