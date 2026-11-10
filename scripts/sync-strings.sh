#!/bin/zsh
# Adds every localizable string the compiler finds in Sources/Wamadu to the String Catalog and marks removed ones stale.
set -euo pipefail
cd "${0:A:h}/.."
# the compiler knows interpolation types (%@, %lld), a fresh build path re-emits every file and keeps the regular cache
rm -rf .build/strings
swift build --product Wamadu --build-path .build/strings -Xswiftc -emit-localized-strings >/dev/null
xcrun xcstringstool sync Sources/Wamadu/Resources/Localizable.xcstrings \
  --stringsdata .build/strings/**/Wamadu.build/**/*.stringsdata
