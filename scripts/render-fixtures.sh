#!/bin/sh
# Render every fixture (popover and sweeps) in light and dark to a directory (default: .build/fixtures).
set -eu
cd "$(dirname "$0")/.."
out="${1:-.build/fixtures}"
mkdir -p "$out"
app="$(scripts/build-app.sh)"
for name in findings killed empty unchanged badConfig swap disk boot; do
  "$app/Contents/MacOS/Reclaim" --render "$name" "$out/$name-light.png"
  "$app/Contents/MacOS/Reclaim" --render "$name" "$out/$name-dark.png" --dark
done
ls "$out"
