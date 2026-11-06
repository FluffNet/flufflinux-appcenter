#!/bin/sh
# No desktop apps/sources are changed. Real transactions use temporary roots;
# the native and long-running queue workers are explicitly simulated fixtures.
set -eu
export CARGO_NET_OFFLINE=true
mkdir -p target/jobs-stress
# Build modes sequentially: their public static-library filename is shared.
cargo test --offline > target/jobs-stress/rust.log 2>&1
cargo clippy --offline --all-targets --features native-tests -- -D warnings > target/jobs-stress/clippy.log 2>&1
cargo build --offline
for suite in test_updates test_full_update_plan test_transaction_retries test_addons; do
    APPCENTER_TEST_BINARY="$PWD/target/debug/flufflinux-appcenter" \
        python3 "tests/integration/$suite.py" > "target/jobs-stress/$suite.log" 2>&1
done
for job_locale in en_US.UTF-8 he_IL.UTF-8 de_DE.UTF-8; do
    LANGUAGE="$job_locale" LANG="$job_locale" \
        python3 tests/integration/test_mixed_jobs_stress.py target/debug/flufflinux-appcenter \
        > "target/jobs-stress/mixed-$job_locale.log" 2>&1
done
. tests/native/build-adapter.sh
for name in parallel_workers removed_download_history cancel_worker updates_manager background_queue catalog_expiry; do
    build_adapter_test "$name"
done
for round in 1 2 3; do
    for name in parallel_workers removed_download_history cancel_worker updates_manager background_queue catalog_expiry; do
        QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen dbus-run-session -- "target/adapter-tests/$name" \
            > "target/jobs-stress/$name-$round.log" 2>&1
    done
done
cargo build --offline --features native-tests --example update-profile
python3 - <<'PY'
import json
from pathlib import Path
seed = json.loads(Path("tests/fixtures/update-progress-catalog.json").read_text())[0]
Path("target/jobs-stress/catalog.json").write_text(json.dumps([
    dict(seed, id=f"org.example.Progress{i:03}", name=f"Progress fixture {i:03}") for i in range(200)]))
PY
rustc tests/queue_memory_probe.rs -o target/jobs-stress/memory-probe
APPCENTER_TEST_TIMEOUT_SECONDS=600 QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop \
    APPCENTER_PROFILE_ITEMS=200 APPCENTER_PROFILE_REPLAN=1 \
    APPCENTER_PROFILE_CATALOG="$PWD/target/jobs-stress/catalog.json" \
    APPCENTER_PROFILE_QML="$PWD/tests/UpdateProfileSoak.qml" \
    dbus-run-session -- target/jobs-stress/memory-probe target/debug/examples/update-profile \
    > target/jobs-stress/three-batch-memory.log 2>&1
for suite in transactions updates downloads_page recovery rtl long_labels queue_stress; do
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
        QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner \
        -input "tests/qml/tst_$suite.qml" > "target/jobs-stress/qml-$suite.log" 2>&1
done
printf 'PASS: isolated real update/removal, native fault/lifecycle, localization and sustained queue-memory stress\n'
