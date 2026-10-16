#!/bin/sh
# Source from a runner in the repository root. Tests link the real Rust state
# machine and thin native adapter, with test-only cache fixture access enabled.
set -eu
cargo build --lib --features native-tests
mkdir -p target/adapter-tests
build_adapter_test() {
    name="$1"
    c++ -std=c++17 -fPIC -Wall -Wextra "tests/native/test_$name.cpp" \
        target/debug/libflufflinux_appcenter.a -o "target/adapter-tests/$name" \
        -include QElapsedTimer -include QFile -include QDir -include QProcess \
        -I/usr/include/KF6/KJobWidgets -I/usr/include/KF6/KStatusNotifierItem \
        $(pkg-config --cflags --libs Qt6Widgets Qt6Quick Qt6Qml Qt6Network Qt6DBus Qt6Test KF6CoreAddons KF6WindowSystem flatpak ostree-1) \
        -lKF6JobWidgets -lKF6StatusNotifierItem -lKF6IconThemes -ldl -lpthread -lm
}
