#!/bin/sh
# Build a Release bundle, sign and notarize it when a Developer ID identity is given, and install it to /Applications.
# Signed path: RECLAIM_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" plus a notarytool keychain profile
# named "reclaim" (`xcrun notarytool store-credentials reclaim`). Without the identity the build stays ad-hoc.
set -eu
cd "$(dirname "$0")/.."
identity="${RECLAIM_SIGN_IDENTITY:-}"
if [ -n "$identity" ]; then
  team="$(printf '%s' "$identity" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
  # A secure timestamp and no injected get-task-allow entitlement are what the notary service checks first.
  app="$(CONFIGURATION=Release scripts/build-app.sh CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" \
         OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)"
  ditto -c -k --keepParent "$app" .build/Reclaim.zip
  # submit --wait exits 0 on a rejection, so read the verdict; `xcrun notarytool log <id> --keychain-profile reclaim` says why.
  xcrun notarytool submit .build/Reclaim.zip --keychain-profile reclaim --wait | tee .build/notarize.log
  grep -q 'status: Accepted' .build/notarize.log || { echo "release: notarization rejected" >&2; exit 1; }
  xcrun stapler staple "$app"
  spctl -a -vv "$app"
  ditto -c -k --keepParent "$app" .build/Reclaim.zip   # re-zip with the ticket stapled: this is the release asset
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
shasum -a 256 .build/Reclaim.zip | cut -d' ' -f1 | sed 's/^/sha256 for the cask: /' >&2
