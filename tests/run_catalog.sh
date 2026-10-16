#!/bin/sh
set -eu
cargo test backend::popularity
. tests/native/build-adapter.sh
build_adapter_test catalog_preferences
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop target/adapter-tests/catalog_preferences "$PWD/qml/Main.qml"
