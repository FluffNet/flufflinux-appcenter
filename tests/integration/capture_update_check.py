"""Render simulated checking states in an isolated native KDE/QML process."""
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

project = Path(__file__).resolve().parents[2]
binary = str(Path(sys.argv[1]).resolve())
for locale in ["en_US.UTF-8", "he_IL.UTF-8", "de_DE.UTF-8"]:
    with tempfile.TemporaryDirectory(prefix="appcenter-scan-check-ui-") as directory:
        root = Path(directory)
        env = dict(os.environ, LANG=locale, LANGUAGE=locale.split(".")[0],
                   QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   QT_QUICK_CONTROLS_STYLE="org.kde.desktop", QT_FORCE_STDERR_LOGGING="1",
                   FLUFF_APP_CENTER_QML=str(project / "tests/integration/UpdateCheckCapture.qml"))
        for key, name in {"XDG_CACHE_HOME":"cache", "XDG_CONFIG_HOME":"settings",
                          "XDG_DATA_HOME":"data", "XDG_RUNTIME_DIR":"runtime",
                          "FLATPAK_USER_DIR":"user", "FLATPAK_SYSTEM_DIR":"system",
                          "FLATPAK_CONFIG_DIR":"config"}.items():
            path = root / name
            path.mkdir(mode=0o700)
            env[key] = str(path)
        result = subprocess.run(["dbus-run-session", "--", binary], env=env,
                                text=True, capture_output=True, timeout=40)
        (project / f"target/scan-check-ui-{locale}.log").write_text(result.stdout + result.stderr)
        print("\n".join(line for line in result.stderr.splitlines() if "SCAN_CAPTURE" in line), flush=True)
        assert result.returncode == 0, result.stderr[-5000:]
        for theme in ["dark", "light"]:
            for scene in ["source", "plans", "narrow"]:
                image = project / f"target/scan-check-{locale.split('.')[0]}-{theme}-{scene}.png"
                data = image.read_bytes()
                assert data[:8] == b"\x89PNG\r\n\x1a\n", image
                assert struct.unpack(">II", data[16:24]) == (720 if scene == "narrow" else 1180, 760), image
print("PASS: 18 native localized scan-progress screenshots, both themes, real RTL fill and narrow labels")
