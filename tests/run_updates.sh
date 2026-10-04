#!/bin/sh
# Real worker tests use temporary offline Flatpak repositories only.
set -eu
. tests/native/build-adapter.sh
build_adapter_test updates_manager
QT_QPA_PLATFORM=offscreen target/adapter-tests/updates_manager
cargo test
cargo build
APPCENTER_TEST_BINARY="$PWD/target/debug/flufflinux-appcenter" python3 tests/integration/test_updates.py
for scale in 1 1.5; do
    QT_SCALE_FACTOR="$scale" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_updates.qml
done
