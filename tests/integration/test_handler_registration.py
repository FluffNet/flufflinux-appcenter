"""Non-mutating to the host: exercise registration entirely in a temp directory."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="appcenter-handler-test-") as directory:
    config = Path(directory) / "mimeapps.list"
    original = "# Distro defaults\n[Default Applications]\ntext/plain=editor.desktop;\napplication/vnd.flatpak=old.desktop;\nx-scheme-handler/appstream=org.kde.discover.urlhandler.desktop;\n[Added Associations]\ntext/plain=another.desktop;\n"
    config.write_text(original)
    def register(mode="add"):
        subprocess.run(["sh", str(ROOT / "scripts/register-flatpak-handler.sh"), str(config), mode], check=True)
    register()
    changed = config.read_text()
    assert "application/vnd.flatpak=flufflinux-appcenter.desktop;old.desktop;" in changed
    assert changed.count("flufflinux-appcenter.desktop;") == 6
    assert "x-scheme-handler/appstream=flufflinux-appcenter.desktop;org.kde.discover.urlhandler.desktop;" in changed
    assert "[Added Associations]\ntext/plain=another.desktop;" in changed
    assert "text/plain=editor.desktop;" in changed
    register()
    assert config.read_text() == changed, "Registration must be idempotent"
    register("remove")
    assert config.read_text() == original, "Removal must preserve previous defaults"
    config.unlink()
    register()
    assert config.read_text().count("flufflinux-appcenter.desktop;") == 6
print("PASS: system handler defaults, preservation, idempotence, removal and first install")
