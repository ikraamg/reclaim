#!/bin/sh
# Generate the Xcode project and build the app bundle (CONFIGURATION=Release for a release build; extra arguments go to xcodebuild, e.g. CODE_SIGN_IDENTITY=...). Prints the bundle path.
set -eu
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-Debug}"
xcodegen generate --quiet
xcodebuild -project Reclaim.xcodeproj -scheme Reclaim -configuration "$configuration" \
  -derivedDataPath .build/DerivedData build -quiet "$@"
echo "$PWD/.build/DerivedData/Build/Products/$configuration/Reclaim.app"
