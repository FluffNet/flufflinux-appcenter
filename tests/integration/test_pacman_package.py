#!/usr/bin/env python3
"""Read-only inspection of fakeroot or a manual archive; never installs it."""
from pathlib import Path
from contextlib import ExitStack
import configparser
import subprocess
import sys
import tempfile

package = Path(sys.argv[1]).resolve(strict=True)
metadata = ((package / ".PKGINFO").read_text() if package.is_dir() else
            subprocess.check_output(["bsdtar", "-xOf", package, ".PKGINFO"], text=True))
values = {}
for line in metadata.splitlines():
    if " = " in line:
        key, value = line.split(" = ", 1)
        values.setdefault(key, []).append(value)
assert values["pkgname"] == ["flufflinux-appcenter"]
assert values["packager"] == ["FluffNet LLC"]
assert int(values["size"][0]) > 0 and int(values["builddate"][0]) >= 0
assert "@" not in metadata, "metadata placeholders must be resolved"
for key in ("conflict", "replaces"):
    assert set(values[key]) == {"discover", "flufflinux-discover"}, values
assert "flufflinux-update" in values["depend"]
assert "kjobwidgets>=6.18" in values["depend"]
assert "kstatusnotifieritem" in values["depend"]
assert values["backup"] == ["etc/flufflinux-appcenter/exclusions.conf"]
with ExitStack() as stack:
    root = package
    if not package.is_dir():
        root = Path(stack.enter_context(tempfile.TemporaryDirectory(prefix="appcenter-package-test-")))
        subprocess.run(["bsdtar", "-xf", package, "-C", root], check=True)
    assert not (root / "etc/xdg/mimeapps.list").exists(), "shared MIME defaults must not be package-owned"
    assert not (root / "etc/xdg/autostart").exists(), "do not inherit Discover's notifier"
    unit = (root / "usr/lib/systemd/user/flufflinux-appcenter.service").read_text()
    assert "ExecStart=/usr/bin/flufflinux-appcenter" in unit
    assert "FLUFF_APP_CENTER_SESSION_SERVICE=1" in unit
    assert "PartOf=graphical-session.target" in unit
    assert "Restart=no" in unit and "[Install]" not in unit
    assert "User=root" not in unit
    assert not (root / "usr/bin/app-center").is_symlink()
    assert not (root / "usr/bin/app-center").exists()
    for name in ("plasma-discover", "discover", "flufflinux-discover"):
        alias = root / "usr/bin" / name
        assert alias.is_symlink()
        assert alias.resolve() == root / "usr/bin/flufflinux-appcenter"
    for name in ("flufflinuxplasmadiscover", "plasmadiscover"):
        alias = root / "usr/share/icons/hicolor/scalable/apps" / (name + ".svg")
        assert alias.is_symlink() and alias.is_file()
        assert alias.resolve().name == "flufflinux-appcenter.svg"
    applications = root / "usr/share/applications"
    legacy = applications / "org.kde.discover.desktop"
    assert legacy.is_symlink() and legacy.is_file()
    assert (applications / "org.kde.discover.urlhandler.desktop").is_symlink()
    visible = []
    for desktop in applications.glob("*.desktop"):
        subprocess.run(["desktop-file-validate", desktop], check=True)
        content = configparser.ConfigParser(interpolation=None)
        content.read(desktop)
        entry = content["Desktop Entry"]
        assert entry["Name"] == "App Center"
        assert entry["Icon"] == "flufflinux-appcenter"
        assert entry["Exec"] == "flufflinux-appcenter --desktop-open %U"
        assert "x-scheme-handler/appstream" in entry["MimeType"].split(";")
        assert content["Desktop Action Updates"]["Exec"] == "flufflinux-appcenter --updates"
        if entry.get("NoDisplay") != "true":
            visible.append(desktop.name)
    assert visible == ["org.kde.discover.desktop"], visible
    assert (root / ".INSTALL").exists()
    subprocess.run(["sh", "-n", root / ".INSTALL"], check=True)
    assert (root / "usr/lib/flufflinux-appcenter/register-flatpak-handler").stat().st_mode & 0o111
    assert (root / "usr/share/licenses/flufflinux-appcenter/LICENSE").is_file()
print("PASS: pacman identity/dependencies/replacements/config backup, executable and icon aliases, one visible legacy launcher, no notifier/shared MIME ownership")
