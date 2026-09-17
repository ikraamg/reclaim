#!/bin/sh
# Build a Release bundle, sign and notarize it when a Developer ID identity is given, and install it to /Applications.
# Signed path: RECLAIM_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" plus a notarytool keychain profile
# named "reclaim" (`xcrun notarytool store-credentials reclaim`). Without the identity the build stays ad-hoc.
# NOTE: the signed path has not been exercised yet - no Developer ID certificate existed when this was written.
set -eu
cd "$(dirname "$0")/.."
identity="${RECLAIM_SIGN_IDENTITY:-}"
if [ -n "$identity" ]; then
  team="$(printf '%s' "$identity" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
  app="$(CONFIGURATION=Release scripts/build-app.sh CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team")"
  ditto -c -k --keepParent "$app" .build/Reclaim.zip
  xcrun notarytool submit .build/Reclaim.zip --keychain-profile reclaim --wait
  xcrun stapler staple "$app"
  spctl -a -vv "$app"
else
  echo "release: no RECLAIM_SIGN_IDENTITY - ad-hoc build, not notarized" >&2
  app="$(CONFIGURATION=Release scripts/build-app.sh)"
fi
codesign -dv "$app" 2>&1 | grep -E '^(Authority|Signature)' >&2 || true

pkill -x Reclaim || true
rm -rf /Applications/Reclaim.app
ditto "$app" /Applications/Reclaim.app

# Re-point the CLI shim if it is the app's shim (Settings installs it against whichever bundle was running).
shim="$HOME/.local/bin/reclaim"
if [ -f "$shim" ] && grep -q 'Reclaim.app/Contents/MacOS/Reclaim" --cli' "$shim"; then
  printf '#!/bin/sh\nexec "/Applications/Reclaim.app/Contents/MacOS/Reclaim" --cli "$@"\n' > "$shim"
fi

open /Applications/Reclaim.app
echo /Applications/Reclaim.app
