#!/bin/sh
set -eu
mkdir -p target
qt_moc="$(pkg-config --variable=libexecdir Qt6Core)/moc"
"$qt_moc" src/catalog_stats.h -o target/moc_catalog_stats_test.cpp
c++ -std=c++17 -fPIC tests/native/test_catalog_stats.cpp src/catalog_stats.cpp \
    target/moc_catalog_stats_test.cpp -o target/test_catalog_stats \
    $(pkg-config --cflags --libs Qt6Core Qt6Network)
target/test_catalog_stats
"$qt_moc" src/catalog_preferences.h -o target/moc_catalog_preferences_test.cpp
c++ -std=c++17 -fPIC tests/native/test_catalog_preferences.cpp \
    target/moc_catalog_preferences_test.cpp -o target/test_catalog_preferences \
    $(pkg-config --cflags --libs Qt6Gui Qt6Qml Qt6Quick)
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop \
    target/test_catalog_preferences "$PWD/qml/Main.qml"
