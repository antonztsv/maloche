#!/bin/zsh
# Builds, signs and packs build/release/maloche-<version>.zip and build/dmg/maloche-<version>.dmg from a clean commit. Usage: scripts/release.sh [--skip-jenkins]
set -euo pipefail
cd "${0:A:h}/.."

CREATE_DMG_EXTRA=()
# --skip-jenkins leaves out the Finder window layout, which needs Automation access and opens Finder windows
[[ "${1:-}" == --skip-jenkins ]] && CREATE_DMG_EXTRA+=(--skip-jenkins)
command -v create-dmg >/dev/null || { echo "create-dmg not found, install it with: brew install create-dmg" >&2; exit 1; }

IDENTITY="${MALOCHE_SIGNING_IDENTITY:-maloche Local Signing}"
FINGERPRINT_FILE="scripts/signing-fingerprint.txt"

for name in MALOCHE_VERSION MALOCHE_BUILD_NUMBER MALOCHE_APPCAST_URL MALOCHE_SIGNING_IDENTITY; do
  [[ -z "${(P)name:-}" ]] || echo "$name=${(P)name}"
done
export MALOCHE_APPCAST_URL="${MALOCHE_APPCAST_URL:-https://github.com/antonztsv/maloche/releases/latest/download/appcast.xml}"
if [[ "$MALOCHE_APPCAST_URL" != https://* ]]; then
  echo "MALOCHE_APPCAST_URL must be an https URL." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Uncommitted changes, commit or stash first." >&2
  exit 1
fi

[[ -f "$FINGERPRINT_FILE" ]] || { echo "$FINGERPRINT_FILE is missing." >&2; exit 1; }
EXPECTED="${MALOCHE_SIGNING_FINGERPRINT:-$(tr -d '[:space:]' < "$FINGERPRINT_FILE")}"
EXPECTED="$(print -r -- "$EXPECTED" | tr a-f A-F)"
ACTUAL="$(security find-certificate -c "$IDENTITY" -Z 2>/dev/null | awk '/SHA-256 hash:/ {print $3; exit}' || true)"
[[ -n "$ACTUAL" ]] || { echo "Signing identity \"$IDENTITY\" not found in the keychain. Not signing." >&2; exit 1; }
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "Certificate \"$IDENTITY\" has SHA-256 ${ACTUAL:-none}, expected $EXPECTED. Not signing." >&2
  exit 1
fi

rm -rf build/release build/dmg build/dmg-source
CERT_SHA1="$(security find-certificate -c "$IDENTITY" -Z 2>/dev/null | awk '/SHA-256 hash:/ {found = ($3 == a)} /SHA-1 hash:/ && found {print $3; exit}' a="$ACTUAL" || true)"
[[ -n "$CERT_SHA1" ]] || { echo "Could not read the SHA-1 of the verified certificate. Not signing." >&2; exit 1; }

MALOCHE_SIGNING_IDENTITY="$CERT_SHA1" scripts/build-app.sh --release
APP="build/maloche.app"

codesign --verify --deep --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -F "Authority=$IDENTITY" || { echo "App is not signed by \"$IDENTITY\"." >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
ZIP="build/release/maloche-$VERSION.zip"
mkdir -p build/release
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "$ZIP"
shasum -a 256 "$ZIP"

# outside build/release so generate_appcast only lists the zip
DMG="build/dmg/maloche-$VERSION.dmg"
mkdir -p build/dmg build/dmg-source
ditto "$APP" build/dmg-source/maloche.app
create-dmg --volname maloche --window-size 540 360 --icon-size 128 \
  --icon maloche.app 140 170 --hide-extension maloche.app --app-drop-link 400 170 \
  --codesign "$CERT_SHA1" "${CREATE_DMG_EXTRA[@]}" "$DMG" build/dmg-source
rm -rf build/dmg-source
codesign --verify --strict "$DMG"
echo "$DMG"
shasum -a 256 "$DMG"

GENERATE_APPCAST=".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ -x "$GENERATE_APPCAST" ]]; then
  echo "To write build/release/appcast.xml, signed with the key in your keychain, run:"
  echo "  $GENERATE_APPCAST --download-url-prefix https://github.com/antonztsv/maloche/releases/download/v$VERSION/ build/release"
fi
