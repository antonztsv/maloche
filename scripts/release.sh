#!/bin/zsh
# Builds, signs and zips build/release/maloche-<version>.zip from a clean commit. Usage: scripts/release.sh
set -euo pipefail
cd "${0:A:h}/.."

IDENTITY="${MALOCHE_SIGNING_IDENTITY:-maloche Local Signing}"
FINGERPRINT_FILE="scripts/signing-fingerprint.txt"

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

scripts/build-app.sh --release
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

GENERATE_APPCAST=".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ -x "$GENERATE_APPCAST" ]]; then
  echo "To write build/release/appcast.xml, signed with the key in your keychain, run:"
  echo "  $GENERATE_APPCAST build/release"
fi
