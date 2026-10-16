#!/bin/sh
# All source/app operations use isolated test fixtures.
set -eu
. tests/native/build-adapter.sh
build_adapter_test catalog_availability
QT_QPA_PLATFORM=offscreen target/adapter-tests/catalog_availability
cargo test --test cache_recovery
cargo build
python3 tests/integration/test_catalog_availability.py target/debug/flufflinux-appcenter
