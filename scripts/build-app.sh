#!/bin/zsh
# Builds build/<Name>.app. Usage: scripts/build-app.sh [--release]
# Default is the dev variant (bundle ID suffix .dev) so manual testing never touches real data.
set -euo pipefail
cd "${0:A:h}/.."

BASE_ID="io.github.antonztsv.maloche"
VERSION="0.1.0"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

case "${1:-}" in
  --release) CONFIG=release; BUNDLE_ID="$BASE_ID"; NAME="maloche" ;;
  "") CONFIG=debug; BUNDLE_ID="$BASE_ID.dev"; NAME="maloche Dev" ;;
  *) echo "Usage: scripts/build-app.sh [--release]" >&2; exit 2 ;;
esac

swift build -c "$CONFIG" --product Maloche
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Maloche" "$APP/Contents/MacOS/Maloche"
# compiled String Catalog goes into the main bundle, Bundle.module would need the resource bundle in the app root
RESOURCES="$BIN_DIR/Maloche_Maloche.bundle/Contents/Resources"
if [[ -d "$RESOURCES" ]]; then
  cp -R "$RESOURCES/" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>Maloche</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

IDENTITY="${MALOCHE_SIGNING_IDENTITY:-maloche Local Signing}"
if ! security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
  echo "Signing identity \"$IDENTITY\" not found. Run scripts/make-signing-cert.sh once." >&2
  exit 1
fi
codesign --force --sign "$IDENTITY" --options runtime --timestamp=none "$APP"
echo "$APP"
