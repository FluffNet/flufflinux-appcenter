#!/bin/sh
# Subprocesses, Flatpak installations and settings are isolated fixtures.
set -eu
. tests/native/build-adapter.sh
for name in updates_manager application_links permissions_manager parallel_workers removed_download_history cancel_worker source_selection source_queue catalog_availability catalog_preferences window_preferences locale; do
    build_adapter_test "$name"
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software "target/adapter-tests/$name"
done
