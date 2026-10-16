#!/bin/sh
set -eu
. tests/native/build-adapter.sh
build_adapter_test network_status
dbus-run-session -- target/adapter-tests/network_status
