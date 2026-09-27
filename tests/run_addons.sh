#!/bin/sh
set -eu
mkdir -p target/addon-tests
"$(pkg-config --variable=libexecdir Qt6Core)/moc" src/flatpak_manager.h -o target/addon-tests/moc_manager.cpp
c++ -std=c++17 -fPIC tests/native/test_application_links.cpp src/flatpak_manager.cpp src/flatpak_sizes.cpp src/flatpak_catalog.cpp \
    target/addon-tests/moc_manager.cpp -o target/addon-tests/application-links \
    $(pkg-config --cflags --libs Qt6Gui Qt6DBus Qt6Network flatpak ostree-1)
QT_QPA_PLATFORM=offscreen target/addon-tests/application-links
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop \
    /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_addons.qml -o target/addon-tests/qml.log,txt
rg 'FAIL!|Totals:' target/addon-tests/qml.log
python3 tests/integration/test_addons.py
