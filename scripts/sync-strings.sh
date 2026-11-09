#!/bin/zsh
# Adds every localizable string found in Sources/Wamadu to the String Catalog and marks removed ones stale.
set -euo pipefail
cd "${0:A:h}/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
xcrun xcstringstool extract --modern-localizable-strings --SwiftUI -o "$TMP" Sources/Wamadu/**/*.swift
xcrun xcstringstool sync Sources/Wamadu/Resources/Localizable.xcstrings --stringsdata "$TMP"/*.stringsdata
