#!/bin/sh
# Isolated simulated workers only. No desktop Flatpak installation is changed.
set -eu
cargo build --offline --features native-tests --example update-profile
for progress_scale in 1 1.5; do
    QT_SCALE_FACTOR="$progress_scale" QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
        QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop \
        /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_progress_stress.qml
done
python3 - <<'PY'
import json
from pathlib import Path
seed=json.loads(Path("tests/fixtures/update-progress-catalog.json").read_text())[0]
Path("target/progress-stress-catalog.json").write_text(json.dumps([
    dict(seed,id=f"org.example.Progress{i:03}",name=f"Progress fixture {i:03}") for i in range(200)]))
PY
for progress_locale in en_US.UTF-8 he_IL.UTF-8; do
    LANGUAGE="$progress_locale" LANG="$progress_locale" QT_FORCE_STDERR_LOGGING=1 \
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop \
        APPCENTER_PROFILE_ITEMS=200 APPCENTER_PROFILE_PROGRESS_STRESS=1 APPCENTER_PROFILE_REPLAN=1 \
        APPCENTER_PROFILE_CATALOG="$PWD/target/progress-stress-catalog.json" \
        APPCENTER_PROFILE_QML="$PWD/tests/ProgressStress.qml" \
        dbus-run-session -- target/debug/examples/update-profile
done
