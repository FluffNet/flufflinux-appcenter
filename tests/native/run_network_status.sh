#!/bin/sh
set -eu
mkdir -p target
"$(pkg-config --variable=libexecdir Qt6Core)/moc" src/network_status.h -o target/test-network-status-moc.cpp
c++ -std=c++17 -fPIC -Wall -Wextra tests/native/test_network_status.cpp src/network_status.cpp target/test-network-status-moc.cpp -o target/test-network-status $(pkg-config --cflags --libs Qt6Core Qt6DBus Qt6Test)
dbus-run-session -- target/test-network-status
