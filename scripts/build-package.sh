#!/bin/sh
# Build as an ordinary user on Fluff Linux; no sudo or implicit dependency install.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Linux ] || { echo 'Build the package on Fluff Linux/Arch Linux.' >&2; exit 1; }
[ "$(id -u)" != 0 ] || { echo 'Run the package build as a regular user.' >&2; exit 1; }
repo=$PWD
mkdir -p build
stage=$(mktemp -d "$repo/build/package.XXXXXX")
mkdir -p "$stage/archive/flufflinux-appcenter"
# Explicit source list excludes build products, screenshots, VM credentials and
# local deployment backups. Preserve edited exclusions without editing the repo.
cp -R Cargo.toml Cargo.lock VERSION LICENSE Makefile build.rs src qml assets data \
    scripts tests "$stage/archive/flufflinux-appcenter/"
exclusions=${EXCLUSIONS_FILE:-/etc/flufflinux-appcenter/exclusions.conf}
if [ -f "$exclusions" ]; then
    cp "$exclusions" "$stage/archive/flufflinux-appcenter/data/exclusions.conf"
elif [ -n "${EXCLUSIONS_FILE:-}" ]; then
    echo "Exclusions file not found: $exclusions" >&2; exit 1
fi
pkgver=$(sed -n 's/^pkgver=//p' packaging/PKGBUILD)
archive="flufflinux-appcenter-$pkgver.tar.gz"
tar -czf "$stage/$archive" -C "$stage/archive" flufflinux-appcenter
checksum=$(sha256sum "$stage/$archive" | cut -d ' ' -f1)
sed "s/@SOURCE_SHA256@/$checksum/" packaging/PKGBUILD > "$stage/PKGBUILD"
cp packaging/flufflinux-appcenter.install "$stage/"
cd "$stage"
makepkg --cleanbuild --noconfirm "$@"
makepkg --packagelist
