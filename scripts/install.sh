#!/bin/sh
# Build the release binary and put `reclaim` on PATH via ~/.local/bin.
set -eu
cd "$(dirname "$0")/.."
swift build -c release
mkdir -p "$HOME/.local/bin"
install -m 755 "$PWD/.build/release/reclaim" "$HOME/.local/bin/reclaim"
"$HOME/.local/bin/reclaim" --self-check
echo "installed: $HOME/.local/bin/reclaim (copy of .build/release/reclaim)"
