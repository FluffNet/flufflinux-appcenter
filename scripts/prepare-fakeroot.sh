#!/bin/sh
# Prepare files and metadata only. Never archive, install or run package hooks.
set -eu
cd "$(dirname "$0")/.."
repo=$PWD
destination="$repo/fakeroot"
exclusions=$1
[ "$(uname -s)" = Linux ] || { echo 'Run make fakeroot on Fluff Linux/Arch Linux.' >&2; exit 1; }
[ -f "$exclusions" ] || { echo "Exclusions file not found: $exclusions" >&2; exit 1; }
[ ! -L "$destination" ] || { echo 'Refusing to replace a symlink at fakeroot.' >&2; exit 1; }
if [ -e "$destination" ] && [ ! -d "$destination" ]; then
    echo 'fakeroot already exists and is not a directory.' >&2; exit 1
fi
build_date=${SOURCE_DATE_EPOCH:-$(date +%s)}
case "$build_date" in ''|*[!0-9]*) echo 'SOURCE_DATE_EPOCH must be an integer timestamp.' >&2; exit 1 ;; esac

mkdir -p build
stage=$(mktemp -d "$repo/build/fakeroot-stage.XXXXXX")
chmod 755 "$stage"
# A failed preparation remains under build/ for inspection. The previous fakeroot
# is untouched until the complete new tree is ready.
# Compilation already finished in the parent make. Copy serially without
# inheriting its parallel job server or unrelated install-prefix overrides.
MAKEFLAGS= MFLAGS= "${MAKE:-make}" --no-print-directory install DESTDIR="$stage" PREFIX=/usr SYSCONFDIR=/etc EXCLUSIONS_FILE="$exclusions"
install -m644 packaging/INSTALL "$stage/.INSTALL"
size=$(du -sk --apparent-size "$stage" | awk '{print $1 * 1024}')
sed -e "s/@BUILD_DATE@/$build_date/" -e "s/@SIZE@/$size/" -e "s/@ARCH@/$(uname -m)/" \
    packaging/PKGINFO.in > "$stage/.PKGINFO"
chmod 644 "$stage/.PKGINFO"

if [ -d "$destination" ]; then
    backup=$(mktemp -d "$repo/build/fakeroot-backup.XXXXXX")
    mv "$destination" "$backup/fakeroot"
    printf 'Previous staging preserved at %s/fakeroot\n' "$backup"
fi
mv "$stage" "$destination"
printf 'Ready: %s (including .PKGINFO and .INSTALL). No package was created or installed.\n' "$destination"
