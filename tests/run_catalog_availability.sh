#!/bin/sh
# Run on Linux. All source/app operations are isolated test fixtures.
set -eu
mkdir -p target/catalog-tests
c++ -std=c++17 -fPIC -Wall -Wextra -Werror tests/native/test_catalog_cache.cpp -o target/catalog-tests/cache $(pkg-config --cflags --libs Qt6Core flatpak ostree-1)
target/catalog-tests/cache
"$(pkg-config --variable=libexecdir Qt6Core)/moc" src/flatpak_manager.h -o target/catalog-tests/moc_manager.cpp
c++ -std=c++17 -fPIC tests/native/test_catalog_availability.cpp src/flatpak_manager.cpp src/flatpak_sizes.cpp src/flatpak_catalog.cpp target/catalog-tests/moc_manager.cpp -o target/catalog-tests/manager $(pkg-config --cflags --libs Qt6Gui Qt6DBus Qt6Network flatpak ostree-1)
QT_QPA_PLATFORM=offscreen target/catalog-tests/manager
c++ -std=c++17 -fPIC tests/native/test_source_worker.cpp -o target/catalog-tests/worker $(pkg-config --cflags --libs Qt6Core Qt6Network flatpak ostree-1)
python3 tests/integration/test_catalog_availability.py target/catalog-tests/worker
