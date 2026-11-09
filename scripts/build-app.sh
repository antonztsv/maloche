#!/bin/zsh
# Builds build/<Name>.app. Usage: scripts/build-app.sh [--release]
# Default is the dev variant (bundle ID suffix .dev) so manual testing never touches real data.
set -euo pipefail
cd "${0:A:h}/.."

BASE_ID="io.github.antonztsv.wamadu"
VERSION="0.1.0"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

if [[ "${1:-}" == "--release" ]]; then
  CONFIG=release; BUNDLE_ID="$BASE_ID"; NAME="wamadu"
else
  CONFIG=debug; BUNDLE_ID="$BASE_ID.dev"; NAME="wamadu Dev"
fi

swift build -c "$CONFIG" --product Wamadu
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Wamadu"

APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Wamadu"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>Wamadu</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

IDENTITY="${WAMADU_SIGNING_IDENTITY:-wamadu Local Signing}"
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  echo "Signing identity \"$IDENTITY\" not found. Run scripts/make-signing-cert.sh once." >&2
  exit 1
fi
codesign --force --sign "$IDENTITY" --options runtime "$APP"
echo "$APP"
