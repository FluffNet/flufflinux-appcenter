#!/usr/bin/env python3
"""Generate KDE palettes in a temporary home and render the real QML UI.

Run under dbus-run-session. Never writes the real user's KDE settings or
changes installed apps. Requires sh tests/run_theme.sh and a built App Center.

APPCENTER_ISOLATED_THEME_TEST=1 QT_FORCE_STDERR_LOGGING=1 \
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=kde QT_QUICK_BACKEND=software \
QT_QUICK_CONTROLS_STYLE=org.kde.desktop XDG_CURRENT_DESKTOP=KDE \
dbus-run-session -- python3 tests/integration/test_theme_matrix.py \
target/theme-shots target/release/flufflinux-appcenter
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
output = Path(sys.argv[1]).resolve()
binary = Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)
# KDE plasma-workspace kcms/colors/ui/AccentColorUI.qml preset swatches.
swatches = [("pink", "#e93a9a"), ("red", "#e93d58"), ("orange", "#e9643a"),
            ("yellow", "#e8cb2d"), ("green", "#3dd425"), ("teal", "#00d3b8"),
            ("blue", "#3daee9"), ("lavender", "#b875dc"), ("purple", "#926ee4"),
            ("gray", "#686b6f")]
assert os.environ.get("APPCENTER_ISOLATED_THEME_TEST") == "1", "Run on an isolated D-Bus with the documented test environment"
with tempfile.TemporaryDirectory(prefix="appcenter-themes-") as directory:
    workspace = Path(directory)
    cases = []
    for mode, scheme in [("dark", "BreezeDark"), ("light", "BreezeLight")]:
        for name, color in [("default", ""), *swatches]:
            case = f"{mode}-{name}"
            home = workspace / case
            config = home / ".config"
            config.mkdir(parents=True)
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config),
                       XDG_CACHE_HOME=str(home / ".cache"), XDG_DATA_HOME=str(home / ".local/share"),
                       QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic",
                       QT_FORCE_STDERR_LOGGING="1")
            command = ["plasma-apply-colorscheme", scheme]
            subprocess.run(command, env=env, check=True, capture_output=True, timeout=15)
            # KDE's CLI ignores the positional scheme when --accent-color is
            # present, so select the scheme first, then apply its accent.
            if color:
                subprocess.run(["plasma-apply-colorscheme", "--accent-color", color],
                               env=env, check=True, capture_output=True, timeout=15)
            cases.append({"name":case, "swatch":color, "config":str(config / "kdeglobals")})
    manifest = output / "cases.json"
    manifest.write_text(json.dumps(cases, indent=2))
    with (output / "catalog.json").open("w") as stream:
        subprocess.run([binary, "--catalog"], cwd=root, stdout=stream, check=True, timeout=60)
    subprocess.run([root / "target/theme-tests/desktop-theme", root, manifest, output],
                   cwd=root, check=True, timeout=180)
print(f"PASS: {len(cases)} KDE palettes, Home/details/updates/settings/About screenshots in {output}")
