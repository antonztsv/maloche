#!/bin/zsh
# Local update test: builds the dev app as 0.1.0 and 0.1.1 into a temporary folder, signs an appcast with the
# Sparkle key from your keychain, serves it on localhost and starts 0.1.0. Then use Settings > General > Check Now.
set -euo pipefail
cd "${0:A:h}/.."

[[ -s scripts/sparkle-public-key.txt ]] || { echo "scripts/sparkle-public-key.txt is missing, see M7-CHECKS.md." >&2; exit 1; }
TMP="$(mktemp -d -t maloche-update)"
FEED="$TMP/feed"
mkdir -p "$FEED"
export MALOCHE_APPCAST_URL="http://localhost:8000/appcast.xml"

MALOCHE_VERSION=0.1.0 MALOCHE_BUILD_NUMBER=1 scripts/build-app.sh >/dev/null
ditto "build/maloche Dev.app" "$TMP/maloche Dev.app"
MALOCHE_VERSION=0.1.1 MALOCHE_BUILD_NUMBER=2 scripts/build-app.sh >/dev/null
ditto -c -k --keepParent "build/maloche Dev.app" "$FEED/maloche-0.1.1.zip"
MALOCHE_APPCAST_URL= scripts/build-app.sh >/dev/null

.build/artifacts/sparkle/Sparkle/bin/generate_appcast "$FEED"

python3 -m http.server 8000 --bind 127.0.0.1 --directory "$FEED" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$TMP"' EXIT
# a still running copy with the same bundle ID would only be activated by open, so wait until it is gone
pkill -f "MacOS/Maloche" || true
while pgrep -f "MacOS/Maloche" >/dev/null; do sleep 0.2; done
APP="$TMP/maloche Dev.app"
open -n "$APP"
sleep 2
echo "Started $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") (build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")) from $APP"
echo "Running: $(pgrep -fl "MacOS/Maloche")"
echo "Settings > General > Check Now should offer 0.1.1."
echo "Press Return when done to stop the server and delete the folder."
read -r
