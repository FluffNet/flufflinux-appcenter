#!/usr/bin/env python3
"""Read-only comparison: immediate local sizes vs libflatpak's resolved plan.
Build with cargo build --example backend-fixture --features native-tests first.
Only the reference transaction contacts the remote; neither path installs apps.
"""
import json
import subprocess
from test_transactions import ROOT, run

for app in ("com.play0ad.zeroad", "com.onepassword.OnePassword", "io.github.mezoahmedii.Picker",
            "org.gnome.Calculator", "org.kde.krita", "com.discordapp.Discord"):
    actual = json.loads(subprocess.check_output([str(ROOT / "target/debug/examples/backend-fixture"), "sizes", app], text=True))
    assert actual["state"] == "ready" and actual["elapsedMs"] < 500, actual
    events = run({"action": "install", "id": app, "estimateOnly": True}, approve=False)
    plan = next(event for event in events if event["type"] == "plan")
    assert actual["appBytes"] == plan["appBytes"], (app, actual, plan)
    assert actual["totalBytes"] == plan["totalBytes"], (app, actual, plan)
    assert actual["appSize"] == plan["appSize"] == actual["singleAppProgressTotal"], (app, actual, plan)
    assert actual["totalSize"] == plan["totalSize"], (app, actual, plan)
    assert not any(event["type"] == "operation" for event in events)
    print(f"PASS {app}: {actual['appSize']} / {actual['totalSize']}; local lookup {actual['elapsedMs']} ms", flush=True)
