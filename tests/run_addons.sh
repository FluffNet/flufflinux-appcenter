#!/bin/sh
set -eu
. tests/native/build-adapter.sh
build_adapter_test application_links
QT_QPA_PLATFORM=offscreen target/adapter-tests/application_links
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_addons.qml
cargo build
APPCENTER_TEST_BINARY="$PWD/target/debug/flufflinux-appcenter" python3 tests/integration/test_addons.py
