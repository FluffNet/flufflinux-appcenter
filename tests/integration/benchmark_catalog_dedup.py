"""Compare local-only --catalog parsing before/after XML deduplication.

Reads existing source metadata without refreshing sources, saving caches or
installing anything. Alternates binaries, checks full catalog equality, and
limits only the test and children to two CPUs.
"""
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

before, after = (str(Path(path).resolve()) for path in sys.argv[1:3])
os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:2])
timings = {"before": [], "after": []}
expected = None
count = 0
for iteration in range(3):
    order = (("before", before), ("after", after))
    if iteration % 2:
        order = tuple(reversed(order))
    for name, binary in order:
        start = time.monotonic()
        result = subprocess.run([binary, "--catalog"], text=True, capture_output=True, timeout=60)
        elapsed = time.monotonic() - start
        assert result.returncode == 0, result.stderr
        apps = json.loads(result.stdout)
        apps.sort(key=lambda app: app["id"])
        digest = hashlib.sha256(json.dumps(apps, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        if expected is None:
            expected = digest
            count = len(apps)
        assert digest == expected, "Catalog contents changed, not just performance"
        timings[name].append(elapsed)
        print(f"{name} run {iteration + 1}: {elapsed:.3f}s, {len(apps)} apps, catalog unchanged", flush=True)
summary = dict(apps=count, catalog_sha256=expected, seconds=timings,
               medians={name: statistics.median(values) for name, values in timings.items()})
print(json.dumps(summary, indent=2), flush=True)
