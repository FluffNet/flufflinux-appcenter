#!/bin/sh
# Merge only App Center's Flatpak associations into the distro-wide defaults.
# Per-user defaults still take precedence. The same script supports DESTDIR.
set -eu
config=$1
mode=${2:-add}
case "$mode" in add|remove) ;; *) exit 2 ;; esac
if [ "$mode" = remove ] && [ ! -f "$config" ]; then exit 0; fi
mkdir -p "$(dirname "$config")"
temporary=$(mktemp "$config.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
input=$config
if [ ! -f "$input" ]; then input=/dev/null; fi
awk -v mode="$mode" '
BEGIN {
    app = "flufflinux-appcenter.desktop"
    split("application/vnd.flatpak application/vnd.flatpak.ref application/vnd.flatpak.repo x-scheme-handler/flatpak x-scheme-handler/flatpak+https x-scheme-handler/appstream", types, " ")
    for (i in types) wanted[types[i]] = 1
}
function missing( key) {
    if (mode == "add") for (key in wanted) if (!seen[key]) print key "=" app ";"
}
/^\[/ {
    if (defaults) missing()
    defaults = ($0 == "[Default Applications]")
    if (defaults) found = 1
}
defaults && /^[^#;][^=]*=/ {
    equals = index($0, "=")
    key = substr($0, 1, equals - 1)
    gsub(/^[ \t]+|[ \t]+$/, "", key)
    if (key in wanted) {
        seen[key] = 1
        count = split(substr($0, equals + 1), values, ";")
        result = mode == "add" ? app ";" : ""
        for (i = 1; i <= count; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", values[i])
            if (values[i] != "" && values[i] != app) result = result values[i] ";"
        }
        if (result != "") print key "=" result
        next
    }
}
{ print }
END {
    if (defaults) missing()
    else if (!found && mode == "add") { print "\n[Default Applications]"; missing() }
}' "$input" > "$temporary"
chmod 644 "$temporary"
mv "$temporary" "$config"
