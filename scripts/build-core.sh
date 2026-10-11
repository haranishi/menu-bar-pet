#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if command -v cargo >/dev/null 2>&1; then
    cargo_bin=$(command -v cargo)
elif [ -x "$HOME/.cargo/bin/cargo" ]; then
    cargo_bin="$HOME/.cargo/bin/cargo"
else
    printf '%s\n' 'Rustが必要です。https://rustup.rs/ から導入してください。' >&2
    exit 1
fi

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
if [ "${1:-}" = --test ]; then
    "$cargo_bin" test --locked --manifest-path "$project_root/rust/Cargo.toml"
fi
"$cargo_bin" build --release --locked --manifest-path "$project_root/rust/Cargo.toml"
