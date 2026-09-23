#!/bin/sh
# Run on Linux from the repository root. All mutations use isolated fixtures.
set -eu
mkdir -p target/update-tests
for name in update_plan permissions install_history; do
    c++ -std=c++17 -fPIC "tests/native/test_$name.cpp" -o "target/update-tests/$name" $(pkg-config --cflags --libs Qt6Core glib-2.0)
    "target/update-tests/$name"
done
c++ -std=c++17 -fPIC tests/native/test_update_sources.cpp -o target/update-tests/update_sources $(pkg-config --cflags --libs Qt6Core flatpak ostree-1)
target/update-tests/update_sources
"$(pkg-config --variable=libexecdir Qt6Core)/moc" src/flatpak_manager.h -o target/update-tests/moc_manager.cpp
c++ -std=c++17 -fPIC tests/native/test_updates_manager.cpp src/flatpak_manager.cpp src/flatpak_sizes.cpp src/flatpak_catalog.cpp target/update-tests/moc_manager.cpp -o target/update-tests/manager $(pkg-config --cflags --libs Qt6Gui Qt6DBus Qt6Network flatpak ostree-1)
QT_QPA_PLATFORM=offscreen target/update-tests/manager
cargo test
cargo build --release
python3 tests/integration/test_updates.py
for scale in 1 1.5; do
    QT_SCALE_FACTOR="$scale" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_updates.qml -o "target/update-tests/qml-$scale.log,txt"
    rg 'FAIL!|Totals:' "target/update-tests/qml-$scale.log"
done
