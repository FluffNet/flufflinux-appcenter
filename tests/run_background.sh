#!/bin/sh
set -eu
mkdir -p target/background-tests
"$(pkg-config --variable=libexecdir Qt6Core)/moc" src/flatpak_manager.h -o target/background-tests/moc_manager.cpp
c++ -std=c++17 -fPIC tests/native/test_background_queue.cpp src/background_queue.cpp src/flatpak_manager.cpp src/flatpak_sizes.cpp src/flatpak_catalog.cpp target/background-tests/moc_manager.cpp \
    -o target/background-tests/queue -I/usr/include/KF6/KJobWidgets -I/usr/include/KF6/KStatusNotifierItem \
    $(pkg-config --cflags --libs Qt6Widgets Qt6DBus Qt6Network KF6CoreAddons flatpak ostree-1) -lKF6JobWidgets -lKF6StatusNotifierItem
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen dbus-run-session -- target/background-tests/queue
