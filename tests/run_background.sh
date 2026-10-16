#!/bin/sh
set -eu
. tests/native/build-adapter.sh
build_adapter_test background_queue
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen dbus-run-session -- target/adapter-tests/background_queue
