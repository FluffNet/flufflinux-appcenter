#!/bin/sh
# Compile the independent source-helper and catalog entry points with every
# enabled warning treated as an error. Never run the privileged helper.
set -eu
cd "$(dirname "$0")/.."
"${CXX:-c++}" -std=c++17 -fPIC -Wall -Wextra -Werror -fsyntax-only \
    src/source_helper.cpp src/flatpak_catalog.cpp \
    $(pkg-config --cflags Qt6Core flatpak ostree-1)
printf 'PASS: source-helper and catalog headers compile without warnings\n'
