#!/bin/sh
# Isolated KDE icon/palette regression test. Never changes desktop settings.
set -eu
cd "$(dirname "$0")/.."
mkdir -p target/theme-tests
theme_flags="$(pkg-config --cflags Qt6Widgets Qt6Quick Qt6Qml) -I/usr/include/KF6/KConfig -I/usr/include/KF6/KIconThemes -I/usr/include/KF6/KColorScheme -I/usr/include/KF6/KConfigCore"
theme_moc="$(pkg-config --variable=libexecdir Qt6Core)/moc"
"$theme_moc" src/desktop_theme.h -o target/theme-tests/moc_desktop_theme.cpp $theme_flags
"$theme_moc" tests/native/test_desktop_theme.cpp -o target/theme-tests/test_desktop_theme.moc $theme_flags
c++ -std=c++17 -fPIC -Wall -Wextra -Werror $theme_flags -Itarget/theme-tests \
    tests/native/test_desktop_theme.cpp target/theme-tests/moc_desktop_theme.cpp \
    -o target/theme-tests/desktop-theme \
    $(pkg-config --libs Qt6Widgets Qt6Quick Qt6Qml) -lKF6IconThemes -lKF6ColorScheme -lKF6ConfigCore
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
    dbus-run-session -- target/theme-tests/desktop-theme
