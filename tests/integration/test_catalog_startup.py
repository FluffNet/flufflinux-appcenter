"""Real KDE cold/warm catalog startup with an isolated disposable disk cache."""
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

binary = str(Path(sys.argv[1]).resolve())
benchmark = Path(__file__).with_name("benchmark_startup.py")
with tempfile.TemporaryDirectory(prefix="appcenter-catalog-cache-") as directory:
    env = dict(os.environ, APPCENTER_TEST_CACHE_HOME=directory)

    def launch(label):
        result = subprocess.run([sys.executable, str(benchmark), binary, "--early"],
                                env=env, text=True, capture_output=True, timeout=60)
        print(f"{label}:\n{result.stdout}", flush=True)
        assert result.returncode == 0, result.stderr + result.stdout
        first = re.search(r"STARTUP_FIRST_FRAME apps (\d+) loading (true|false)", result.stdout)
        assert first, result.stdout
        return int(first[1]), first[2] == "true", result.stdout

    count, loading, _ = launch("COLD")
    assert count == 0 and loading
    cache, = Path(directory).rglob("application-list.json")
    data = json.loads(cache.read_text())
    assert len(data["apps"]) > 100
    timestamp = cache.stat().st_mtime_ns
    count, loading, output = launch("WARM")
    assert count == len(data["apps"]) and not loading
    assert "catalog-cache-ready" in output
    assert cache.stat().st_mtime_ns == timestamp, "Warm startup should neither parse nor rewrite the list"

    # Expiry should refresh in the background without an empty first frame.
    data["savedAt"] = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=2)).isoformat(timespec="milliseconds")
    cache.write_text(json.dumps(data))
    count, loading, _ = launch("EXPIRED")
    assert count == len(data["apps"]) and loading
    assert json.loads(cache.read_text())["savedAt"] != data["savedAt"]
    print("PASS: cold parse, warm first-frame app list without loading, unchanged warm cache, and visible expired-list background refresh")
