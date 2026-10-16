#!/usr/bin/env python3
"""Real executable + production UI; isolated config/socket, no app transactions."""
from pathlib import Path
import json
import os
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[2]
binary = Path(os.environ.get("APPCENTER_TEST_BINARY", repo / "target/release/flufflinux-appcenter"))
with tempfile.TemporaryDirectory(prefix="appcenter-cli-") as temporary:
    root = Path(temporary)
    root.chmod(0o700)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(root), XDG_CONFIG_HOME=str(root / "config"),
               XDG_CACHE_HOME=str(root / "cache"), QT_QPA_PLATFORM="offscreen",
               QT_QUICK_BACKEND="software", QT_FORCE_STDERR_LOGGING="1",
               FLUFF_APP_CENTER_QML=str(repo / "tests/integration/CliSmoke.qml"))
    def run(args, **kwargs):
        return subprocess.run([binary, *args], env=env, capture_output=True, text=True, timeout=25, **kwargs)
    # Help/introspection must work on a terminal without any display/platform plugin.
    display = env["QT_QPA_PLATFORM"]
    env["QT_QPA_PLATFORM"] = "not-a-platform"
    for flag, expected in [("--help", "--search"), ("--help-all", "--mime"), ("--version", "2026.10"),
                           ("--author", "FluffNet LLC"), ("--license", "MIT"),
                           ("--listmodes", "Browsing"), ("--listbackends", "flatpak-backend")]:
        result = run([flag]); assert result.returncode == 0 and expected in result.stdout, result
    assert run(["--version"]).stdout == "App Center 2026.10\n"
    for args in [["--headless-update"], ["--test", "old.qml"]]:
        result = run(args); assert result.returncode != 0 and result.stderr, result
    env["QT_QPA_PLATFORM"] = display
    log = root / "events.log"
    def wait_for(predicate, offset=0):
        for _ in range(400):
            text = log.read_text()[offset:]
            if predicate(text): return text
            assert first.poll() is None, log.read_text()
            time.sleep(0.05)
        raise AssertionError(log.read_text()[offset:])
    def state_is(text, **expected):
        for line in text.splitlines():
            if "CLI_STATE " not in line: continue
            state = json.loads(line.split("CLI_STATE ", 1)[1])
            assert state["updates"] == "idle", "CLI navigation must never check for updates"
            if all(state.get(key) == value for key, value in expected.items()): return True
        return False
    with log.open("w") as output:
        first = subprocess.Popen([binary, "Telegram & friends", "--desktopfile=org.kde.discover.desktop"],
                                 env=env, stdout=output, stderr=output)
        try:
            wait_for(lambda text: state_is(text, search="Telegram & friends"))
            cases = [(["--search=משחקים \"chess\""], {"search":"משחקים \"chess\""}),
                     (["telegram"], {"search":"telegram"}),
                     (["google", "chrome"], {"search":"google chrome"}),
                     (["--serach", "Telegram"], {"search":"--serach Telegram"}),
                     (["--search"], {"search":"--search"}),
                     (["--mode=nope"], {"search":"--mode=nope", "category":"All Apps"}),
                     (["--", "--updates"], {"search":"--updates", "category":"All Apps"}),
                     (["--category", "Games"], {"category":"Games", "search":""}),
                     (["--category=Viewer"], {"rawCategory":"Viewer"}),
                     (["--mime", "APPLICATION/PDF"], {"mime":"application/pdf", "rawCategory":""}),
                     (["--mode", "Installed"], {"category":"Installed", "mime":""}),
                     (["--mode=Update"], {"category":"Updates"}),
                     (["--mode=Search"], {"category":"All Apps", "search":""}),
                     (["--mode=Sources"], {"settings":True}),
                     (["--mode=About"], {"about":True}),
                     (["--updates"], {"category":"Updates", "settings":False, "about":False}),
                     (["--mode=Browsing"], {"category":"All Apps", "settings":False, "about":False})]
            for args, expected in cases:
                offset = len(log.read_text())
                result = run(args); assert result.returncode == 0, result.stderr
                wait_for(lambda text: state_is(text, **expected), offset)
            # Errors are presented in the running window, not silently swallowed.
            for args, marker in [(["--application", "org.invalid.DoesNotExist"], "No matching Flatpak was found"),
                                 (["--local-filename", "missing file.flatpakref"], "CLI_ERROR")]:
                offset = len(log.read_text()); result = run(args, cwd=root)
                assert result.returncode == 0, result.stderr
                wait_for(lambda text: marker in text, offset)
            offset = len(log.read_text())
            assert run(["--desktop-open", "appstream://org.invalid.DoesNotExist"]).returncode == 0
            wait_for(lambda text: "CLI_HOME" in text, offset)
            assert "CLI_ERROR" not in log.read_text()[offset:]
            assert "TypeError" not in log.read_text() and "ReferenceError" not in log.read_text(), log.read_text()
        finally:
            first.terminate(); first.wait(timeout=10)
print("PASS: CLI introspection/errors, first-launch bare search, live IPC multi-word/fallback searches, categories/MIME/all six modes, no automatic updates")
