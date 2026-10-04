#!/bin/sh
# Build the Rust helper and catalog paths. Never run the privileged helper.
set -eu
cd "$(dirname "$0")/.."
cargo check --all-targets
printf 'PASS: Rust backend, helper and native adapters build\n'
