#!/bin/sh
# Real worker tests use temporary offline Flatpak repositories only.
set -eu
. tests/native/build-adapter.sh
build_adapter_test updates_manager
QT_QPA_PLATFORM=offscreen target/adapter-tests/updates_manager
cargo test
cargo build
APPCENTER_TEST_BINARY="$PWD/target/debug/flufflinux-appcenter" python3 tests/integration/test_updates.py
APPCENTER_TEST_BINARY="$PWD/target/debug/flufflinux-appcenter" python3 tests/integration/test_full_update_plan.py
for scale in 1 1.5; do
    QT_SCALE_FACTOR="$scale" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_updates.qml
done
cargo build --offline --features native-tests --example update-profile
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
QT_QUICK_CONTROLS_STYLE=org.kde.desktop APPCENTER_PROFILE_ITEMS=4 \
APPCENTER_PROFILE_CATALOG="$PWD/tests/fixtures/update-progress-catalog.json" \
APPCENTER_PROFILE_QML="$PWD/tests/UpdateProgressRows.qml" \
dbus-run-session -- target/debug/examples/update-profile
