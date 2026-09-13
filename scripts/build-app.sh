#!/bin/sh
# Generate the Xcode project and build the app bundle. Prints the bundle path.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Reclaim.xcodeproj -scheme Reclaim -configuration Debug \
  -derivedDataPath .build/DerivedData build -quiet
echo "$PWD/.build/DerivedData/Build/Products/Debug/Reclaim.app"
